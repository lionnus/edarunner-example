#!/usr/bin/env bash
# machine_check.sh [-c cores] [-g scratch_gb] [-m ram_gb] [host ...]
# One line per host: cores, load, free cores, free RAM, the largest writable scratch
# and its free GB, and FIT when the host has what a job needs. One ssh per host, in
# parallel. MC_HOSTS names the hosts when no argument does; MC_SCRATCH the roots.
set -u
need_c=0 need_g=0 need_m=0
while getopts c:g:m: o; do
  case $o in c) need_c=$OPTARG ;; g) need_g=$OPTARG ;; m) need_m=$OPTARG ;; *) exit 2 ;; esac
done
shift $((OPTIND - 1))
hosts=${*:-${MC_HOSTS:-hostA hostB}}
roots=${MC_SCRATCH:-/scratch /tmp}

probe='
best=0 mount=-
for d in '"$roots"'; do
  [ -w "$d" ] || continue
  a=$(df -BG --output=avail "$d" | tail -1 | tr -dc 0-9)
  [ "${a:-0}" -gt "$best" ] && best=$a mount=$d
done
echo "$(nproc) $(cut -d" " -f1 /proc/loadavg) $(free -g | awk "/^Mem:/{print \$7}") $best $mount"'

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for h in $hosts; do
  timeout 20 ssh -n -o BatchMode=yes -o ConnectTimeout=8 "$h" "$probe" > "$tmp/$h" 2>/dev/null &
done
wait

printf '%-12s %5s %6s %5s %7s %7s %-9s %s\n' HOST CORES LOAD FREE RAM_GB DISK_GB MOUNT FIT
for h in $hosts; do
  read -r cores load ram disk mount < "$tmp/$h" || { printf '%-12s unreachable\n' "$h"; continue; }
  awk -v h="$h" -v c="$cores" -v l="$load" -v r="$ram" -v d="$disk" -v m="$mount" \
      -v nc="$need_c" -v ng="$need_g" -v nm="$need_m" 'BEGIN {
    free = c - l; if (free < 0) free = 0
    fit = (free >= nc && d >= ng && r >= nm) ? "FIT" : "-"
    printf "%-12s %5d %6.1f %5d %7d %7d %-9s %s\n", h, c, l, free, r, d, m, fit }'
done
