#
# Defines yank aliases.
#
# Authors:
#   Daniel Carrillo
#

# Return if requirements are not found.
if (( ! $+commands[yank] )); then
  return 1
fi

#
# Aliases
#

alias yenv="env | yank -d ="     # yank environment variables

#
# Piping aliases
#

alias yl="yank -l"               # yank a whole line from command output
alias yle="yank -l -- sh"        # yank a whole line from command output and
                                 # exec the line as a command
