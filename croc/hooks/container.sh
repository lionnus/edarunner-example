#!/usr/bin/env bash
# container.sh <cmd> [args...]: run one stage command inside the tool image, or directly.
#
# EDR_CONTAINER names the image, for example hpretl/iic-osic-tools:2025.12. If it is
# empty, the command runs directly. EDR_RUNTIME says how the site runs the image: oseda,
# apptainer, singularity, docker or none. If it is unset, the first one found on PATH is
# used. For apptainer and singularity, EDR_SIF_DIR holds <name>_<tag>.sif; if that file
# is missing, the image is pulled from the registry.
#
# `sync.after` copies this file to <run tree>/.edr/.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
img=${EDR_CONTAINER:-}
rt=${EDR_RUNTIME:-}
if [ -z "$rt" ]; then
  rt=none
  for r in oseda apptainer singularity docker; do
    command -v "$r" >/dev/null && { rt=$r; break; }
  done
fi
[ -n "$img" ] || rt=none
name=${img%:*} tag=${img##*:}
export IIC_OSIC_TOOLS_QUIET=1
echo "container.sh: runtime $rt, image ${img:-none}: $*"

case $rt in
  none)
    # Inside the IIC-OSIC-TOOLS image, as in CI, the image's bashrc puts the tools on PATH.
    if [ -f /headless/.bashrc ]; then
      exec bash -c 'export TOOLS=${TOOLS:-/foss/tools}; . /headless/.bashrc >/dev/null 2>&1; exec "$@"' bash "$@"
    fi
    exec "$@" ;;
  oseda)
    exec oseda "-$tag" "$@" ;;
  apptainer|singularity)
    sif=${EDR_SIF_DIR:-}/${name##*/}_$tag.sif
    [ -f "$sif" ] || sif=docker://$img
    echo "container.sh: $sif"
    exec "$rt" exec --bind "$root" "$sif" bash -c 'export TOOLS=${TOOLS:-/foss/tools}; . /headless/.bashrc >/dev/null 2>&1; exec "$@"' bash "$@" ;;
  docker)
    # The image's entrypoint sources its bashrc, and --skip runs the command without a desktop.
    exec docker run --rm --user "$(id -u):$(id -g)" -e UID="$(id -u)" -e GID="$(id -g)" \
      -e IIC_OSIC_TOOLS_QUIET=1 -v "$root:$root" -w "$PWD" "$img" --skip "$@" ;;
  *)
    echo "container.sh: unknown EDR_RUNTIME '$rt'" >&2; exit 2 ;;
esac
