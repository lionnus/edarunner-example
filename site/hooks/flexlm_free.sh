#!/usr/bin/env bash
# flexlm_free.sh <port@server> <feature>: the seat probe for one FlexLM feature.
# It prints `free total` on one line, which is what a [tools.<name>] probe must print.
# It exits with 1 when lmstat doesn't list the feature, and the driver then lets the
# stage run anyway.
set -uo pipefail
server=$1 feature=$2
lmutil lmstat -a -c "$server" -f "$feature" | awk -v f="$feature:" '
  $1 == "Users" && $3 == f { print $6 - $11, $6; found = 1; exit }
  END { exit !found }'
