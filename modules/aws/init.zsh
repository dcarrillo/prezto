#
# Defines aws cli aliases/functions.
#
# Authors:
#   Daniel Carrillo
#

# Get the output parameter
zstyle -s ':prezto:module:aws' output '_aws_output' || _aws_output='table'
zstyle -s ':prezto:module:aws' profile '_aws_profile' || _aws_profile='default'

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
    aws ec2 describe-volumes ---profile $profile --output ${_aws_output} \
        --query 'Volumes[*].{id:VolumeId,tag:Tags[0].Value,at:Attachments[0].InstanceId,size:Size}'
}

function aws_elb {
    local profile=$(_get_aws_profile)
    aws elb describe-load-balancers --profile $profile --output ${_aws_output} \
        --query 'LoadBalancerDescriptions[*].{chz:CanonicalHostedZoneName,vpc:VPCId,name:LoadBalancerName}'
}

function aws_elb2 {
    local profile=$(_get_aws_profile)
    aws elbv2 describe-load-balancers --profile $profile --output ${_aws_output} \
        --query "LoadBalancers[*].{dns:DNSName,vpc:VpcId,name:LoadBalancerName,subnets:AvailabilityZones[*].SubnetId | join(',', @)}"
}

function aws_userdata {
    local profile=$(_get_aws_profile)
    aws ec2 describe-instance-attribute --profile $profile --output text \
        --attribute userData --instance-id $1 \
        --query 'UserData.Value' --profile $profile --output text | base64 -d
}

function aws_vpc {
    local profile=$(_get_aws_profile)
    aws ec2 describe-vpcs --profile $profile --output ${_aws_output} \
        --query 'Vpcs[*].{id:VpcId,cidr:CidrBlock,tag:Tags[0].Value}'
}

function aws_ag {
    local profile=$(_get_aws_profile)
    aws autoscaling describe-auto-scaling-groups --profile $profile --output ${_aws_output} \
        --query 'AutoScalingGroups[*].{name:AutoScalingGroupName,az:VPCZoneIdentifier}'
}

function aws_ami {
    local profile=$(_get_aws_profile)
    aws ec2 describe-images --profile $profile --output ${_aws_output} \
        --owner self --query 'Images[*].{id:ImageId,name:Name,virt:VirtualizationType,st:State}'
}
