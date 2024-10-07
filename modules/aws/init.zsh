#
# Defines aws cli aliases/functions.
#
# Authors:
#   Daniel Carrillo
#

# Get the output parameter
zstyle -s ':prezto:module:aws' output '_aws_output' || _aws_output='table'
zstyle -s ':prezto:module:aws' show_region '_aws_region' || _aws_region='false'
zstyle -s ':prezto:module:aws' profile '_aws_profile' || _aws_profile='default'
zstyle -s ':prezto:module:aws' sso '_aws_sso' || _aws_sso='false'

# Return if requirements are not found.
if (( ! $+commands[aws] )); then
  return 1
fi

function _get_aws_profile {
    if [[ -z "${AWS_PROFILE+1}" ]]; then
        echo ${_aws_profile}
    else
        echo $AWS_PROFILE
    fi
}

function aws_i {
    local profile=$(_get_aws_profile)
    aws ec2 describe-instances --profile $profile --output ${_aws_output} \
        --query 'Reservations[].Instances[].[Tags[?Key==`Name`] | [0].Value, LaunchTime, State.Name,
                 InstanceType, VpcId, InstanceId, Placement.AvailabilityZone, PrivateIpAddress, PublicIpAddress]'
}

function aws_ebs {
    local profile=$(_get_aws_profile)
    aws ec2 describe-volumes --profile $profile --output ${_aws_output} \
        --query 'Volumes[].[Tags[?Key==`Name`] | [0].Value, VolumeId, Attachments[0].InstanceId, Size, VolumeType, Iops, AvailabilityZone]'
}

function aws_elb {
    local profile=$(_get_aws_profile)
    aws elb describe-load-balancers --profile $profile --output ${_aws_output} \
        --query "LoadBalancerDescriptions[*].{type:'elb',scheme:Scheme,dns:DNSName,vpc:VPCId,name:LoadBalancerName,subnets:Subnets[*] | join(',', @)}"

    local profile=$(_get_aws_profile)
    aws elbv2 describe-load-balancers --profile $profile --output ${_aws_output} \
        --query "LoadBalancers[*].{type:Type,scheme:Scheme,dns:DNSName,vpc:VpcId,name:LoadBalancerName,subnets:AvailabilityZones[*].SubnetId | join(',', @)}"
}

function aws_userdata {
    local profile=$(_get_aws_profile)
    aws ec2 describe-instance-attribute --profile $profile --output text \
        --attribute userData --instance-id $1 \
        --query 'UserData.Value' | base64 -d
}

function aws_vpc {
    local profile=$(_get_aws_profile)
    aws ec2 describe-vpcs --profile $profile --output ${_aws_output} \
        --query 'Vpcs[*].{id:VpcId,cidr:CidrBlock,tag:Tags[0].Value}'
}

function aws_subnets {
    local profile=$(_get_aws_profile)
    aws ec2 describe-subnets --profile $profile --output text \
        --query 'Subnets[].[Tags[?Key==`Name`] | [0].Value, SubnetId, VpcId, CidrBlock]' \
        | sort -k1 | column -t
}

function aws_ag {
    local profile=$(_get_aws_profile)
    aws autoscaling describe-auto-scaling-groups --profile $profile --output ${_aws_output} \
        --query 'AutoScalingGroups[*].{name:AutoScalingGroupName,az:VPCZoneIdentifier}'
}

function aws_ami {
    local profile=$(_get_aws_profile)
    aws ec2 describe-images --profile $profile --output ${_aws_output} \
        --owner self --query 'Images[*].{date:CreationDate,id:ImageId,name:Name,virt:VirtualizationType,st:State}'
}

function aws_kms_decrypt {
    local profile=$(_get_aws_profile)

    if [[ -z $1 ]]; then
        echo "String is missing"
        return 1
    fi
    aws kms --profile $profile decrypt --ciphertext-blob fileb://<(base64 -d <<<$1) \
        --output text --query Plaintext | base64 -d
}

function aws_ssm_session {
    local profile=$(_get_aws_profile)

    if [[ -z $1 ]]; then
        echo "Instance id is missing"
        return 1
    fi
    aws ssm start-session --profile $profile --target $1
}

function aws_ssm_session_any {
    local profile=$(_get_aws_profile)
    local id

    if [[ -z $1 ]]; then
        echo "Instance name is missing"
        return 1
    fi

    id=$(aws ec2 describe-instances --profile $profile --output text \
        --filter "Name=tag:Name,Values=$1" "Name=instance-state-name,Values=running" \
        --query 'Reservations[0].Instances[0].InstanceId')
    if [[ $2 == "ssh" ]]; then
        shift 2
        AWS_PROFILE=$profile ssh $id $@
    else
        aws ssm start-session --profile $profile --target $id
    fi
}

function aws_ssm_parameters {
    local profile=$(_get_aws_profile)
    aws ssm describe-parameters --profile $profile --output ${_aws_output} \
        --query 'Parameters[].[Name,Type]'
}

function aws_ssm_get_parameter {
    local profile=$(_get_aws_profile)
    local parameter=$1

    aws ssm get-parameter --profile $profile --output text \
        --name $parameter --with-decryption --query "Parameter.Value"
}

function aws_cf {
    local profile=$(_get_aws_profile)

    if ! type "jq" > /dev/null; then
      echo "ERROR: this function needs jq to be installed"
      return 1
    fi

    aws cloudfront list-distributions --profile $profile --output json \
        --query "DistributionList.Items[*].{id:Id,domain:DomainName,status:Status,
                 origin:Origins.Items[].DomainName | join(' ', @), aliases:Aliases.Items | join(' ', @)}" \
        | jq -r ".[] | [.id, .domain, .aliases, .status, .origin] | @csv" | tr -d '"' | column --separator="," --table
}

function aws_eks {
    local profile=$(_get_aws_profile)

    for cluster in $(aws eks list-clusters --output text --query 'clusters'); do
        aws eks describe-cluster --name $cluster --output ${_aws_output} \
          --query "cluster.{name:name,endpoint:endpoint,access:resourcesVpcConfig.publicAccessCidrs | join(' ',@),issues:health.issues | join(' ',@)}"
    done
}

# ~/.ssh/config
#
# Host i-*
#    ProxyCommand sh -c "aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters 'portNumber=%p'"
#    User <your_user>
function ssh_aws_any {
    host=$1
    shift
    extra_params=$@
    aws_ssm_session_any $host ssh $extra_params
}

function aws_switch_profile {
    local region
    local credentials

    if [[ -z $1 ]]; then
        echo "Profile can't be an empty string"
        return 1
    fi

    echo "Activating profile $1..."
    unset -m "AWS_*"
    export AWS_PROFILE=$1
    if [[ -f ~/.aws/credentials ]]; then #&& (( ! ${+AWS_DEFAULT_REGION} ))
      region=$(aws configure get region)
      if [[ ! -z $region ]]; then
        export AWS_DEFAULT_REGION=$region
      else
        unset AWS_DEFAULT_REGION
      fi

      if [[ ${_aws_sso} == "true" ]]; then
        credentials=$(aws-export-credentials --env-export 2>&1)

        if [[ $credentials =~ "has expired" ]]; then
            aws sso login
            credentials=$(aws-export-credentials --env-export)
        fi

        eval $credentials
      fi
    fi
}

function aws_deactivate_profile {
    echo "Deactivating aws profile..."
    unset -m "AWS_*"
}
