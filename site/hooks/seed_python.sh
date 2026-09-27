#!/usr/bin/env bash
# seed_python.sh <host> <root> <mount>
# A `sync.after` hook for flows that keep a Python venv in their tree. It copies the uv
# interpreter onto the host's local scratch and runs `uv sync` there, so the venv never
# reads over NFS. A single NFS hiccup inside a venv can kill a simulation hours in.
#   [sync]
#   after = "bash {site_dir}/hooks/seed_python.sh {host} {root} {mount}"
set -uo pipefail
host=$1 root=$2 mount=$3
ssh -n -o BatchMode=yes "$host" "
  set -e
  d='$mount/$USER/uvpython'; mkdir -p \"\$d\"
  for src in \$HOME/.local/share/uv/python/cpython-*-linux-x86_64-gnu; do
    [ -d \"\$src\" ] || continue
    t=\"\$d/\$(basename \$src)\"
    # A copy that an earlier call left unfinished fails to run, so copy it again.
    \"\$t/bin/python3\" -c '' 2>/dev/null || { rm -rf \"\$t\"; cp -a \"\$src\" \"\$t\"; }
  done
  cd '$root' && UV_PYTHON_INSTALL_DIR=\"\$d\" UV_CACHE_DIR='$mount/$USER/uv-cache' uv sync -q
  readlink -f '$root/.venv/bin/python' | grep -q \"^$mount/\" || echo 'WARN venv python is not on host scratch'
"
