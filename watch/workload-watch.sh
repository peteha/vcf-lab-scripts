#!/usr/bin/env bash
# workload-watch.sh: prove an upgrade does not touch the workloads.
#
# Pings (and optionally polls HTTP on) a few workload targets every second, prints
# one line per interval, logs every probe, and prints a loss summary on Ctrl+C.
# Run it in a Terminal on the lab desktop through the whole management domain
# upgrade: an unbroken run of "ok" is the evidence.
#
#   bash workload-watch.sh 10.1.2.21 10.1.2.22
#   bash workload-watch.sh --http https://app.site-a.vcf.lab 10.1.2.21
#
# Options:
#   --interval N   seconds between rounds (default 1)
#   --http URL     also GET this URL each round (repeatable; any 2xx/3xx is ok)
#   --log FILE     log file (default ~/workload-watch-<date>.log)
# Read-only: it only sends ping and GET.
set -uo pipefail

INTERVAL=1
HTTP=()
LOG="$HOME/workload-watch-$(date +%Y%m%d-%H%M%S).log"
TARGETS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --interval) INTERVAL="$2"; shift ;;
    --http) HTTP+=("$2"); shift ;;
    --log) LOG="$2"; shift ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    -*) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
    *) TARGETS+=("$1") ;;
  esac
  shift
done
[ ${#TARGETS[@]} -gt 0 ] || [ ${#HTTP[@]} -gt 0 ] || { echo "give at least one target or --http URL (try --help)" >&2; exit 2; }

# Counters are indexed arrays (one slot per target), so bash 3.2 works too.
ALL=(${TARGETS[@]+"${TARGETS[@]}"} ${HTTP[@]+"${HTTP[@]}"})
NT=${#TARGETS[@]}
SENT=(); LOST=(); LASTBAD=()
for i in "${!ALL[@]}"; do SENT[i]=0; LOST[i]=0; LASTBAD[i]=-; done
START=$(date '+%F %T')

summary() {
  echo
  echo "== workload-watch summary: $START to $(date '+%F %T')"
  for i in "${!ALL[@]}"; do
    printf '  %-40s sent %6d  lost %4d  last loss %s\n' "${ALL[i]}" "${SENT[i]}" "${LOST[i]}" "${LASTBAD[i]}"
  done
  echo "  log: $LOG"
  exit 0
}
trap summary INT TERM

echo "workload-watch: ${ALL[*]}  (every ${INTERVAL}s, log $LOG, Ctrl+C for the summary)"
while :; do
  ts=$(date '+%T'); line="$ts"
  for (( i=0; i<NT; i++ )); do
    t=${ALL[i]}
    SENT[i]=$(( SENT[i] + 1 ))
    if ping -c1 -W1 "$t" >/dev/null 2>&1; then r=ok; else r=LOST; LOST[i]=$(( LOST[i] + 1 )); LASTBAD[i]=$ts; fi
    line="$line  $t:$r"; echo "$(date '+%F %T') ping $t $r" >> "$LOG"
  done
  for (( i=NT; i<${#ALL[@]}; i++ )); do
    u=${ALL[i]}
    SENT[i]=$(( SENT[i] + 1 ))
    code=$(curl -ks -o /dev/null -m 3 -w '%{http_code}' "$u" 2>/dev/null); code=${code:-000}
    case "$code" in 2*|3*) r=ok ;; *) r="LOST($code)"; LOST[i]=$(( LOST[i] + 1 )); LASTBAD[i]=$ts ;; esac
    line="$line  $u:$r"; echo "$(date '+%F %T') http $u $code" >> "$LOG"
  done
  tot=0; for i in "${!ALL[@]}"; do tot=$(( tot + LOST[i] )); done
  echo "$line   lost so far: $tot"
  sleep "$INTERVAL"
done
