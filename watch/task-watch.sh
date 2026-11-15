#!/usr/bin/env bash
# task-watch.sh: show SDDC Manager's lifecycle tasks in a Terminal, refreshed.
#
# Long upgrades (fleet lifecycle, VCF Operations, the domain components) run for
# far longer than a screen-recording session lasts. This keeps the current state
# on one screen, so a single screenshot shows progress without clicking through
# the UI. Read-only: it gets a token and lists tasks.
#
#   bash task-watch.sh --host sddcmanager-a.site-a.vcf.lab
#
# Options:
#   --host H       SDDC Manager FQDN (required)
#   --user U       API user (default administrator@vsphere.local)
#   --every N      seconds between refreshes (default 30)
#   --all          include finished tasks, not just running ones (last 15)
#   --prompt       type the password instead of using the lab standard one
# Password: the hosted lab's standard password, sent on stdin to curl, never in
# argv. Needs curl and python3 (both on the lab desktop).
set -uo pipefail

HOST=""; USER_NAME="administrator@vsphere.local"; EVERY=30; ALL=no
LAB_PASSWORD='VMware123!VMware123!'
while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST="$2"; shift ;;
    --user) USER_NAME="$2"; shift ;;
    --every) EVERY="$2"; shift ;;
    --all) ALL=yes ;;
    --prompt) read -rsp "password for $USER_NAME: " LAB_PASSWORD; echo ;;
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done
[ -n "$HOST" ] || { echo "--host is required (try --help)" >&2; exit 2; }

token() {
  python3 -c 'import json,sys; print(json.dumps({"username":sys.argv[1],"password":sys.stdin.read().rstrip("\n")}))' "$USER_NAME" <<<"$LAB_PASSWORD" |
    curl -ks -m 20 -X POST "https://$HOST/v1/tokens" -H 'Content-Type: application/json' --data-binary @- |
    python3 -c 'import json,sys; print(json.load(sys.stdin).get("accessToken",""))' 2>/dev/null
}

TOKEN=""; GOT=0
while :; do
  now=$(date +%s)
  if [ -z "$TOKEN" ] || [ $(( now - GOT )) -gt 2400 ]; then TOKEN=$(token); GOT=$now; fi
  clear
  echo "SDDC Manager tasks on $HOST   $(date '+%F %T')   (every ${EVERY}s, Ctrl+C to stop)"
  echo
  if [ -z "$TOKEN" ]; then
    echo "  could not get an API token (host, user or password?). Retrying."
  else
    curl -ks -m 30 -H "Authorization: Bearer $TOKEN" "https://$HOST/v1/tasks" |
    ALL="$ALL" python3 -c '
import json, os, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("  no task list returned"); sys.exit(0)
items = d.get("elements", d if isinstance(d, list) else [])
items.sort(key=lambda t: t.get("creationTimestamp", ""), reverse=True)
if os.environ["ALL"] != "yes":
    items = [t for t in items if t.get("status") in ("IN_PROGRESS", "PENDING", "Pending", "In Progress")]
if not items:
    print("  no running tasks")
for t in items[:15]:
    subs = t.get("subTasks") or []
    done = sum(1 for s in subs if s.get("status") == "SUCCESSFUL")
    prog = ("%d/%d steps" % (done, len(subs))) if subs else ""
    print("  %-19s  %-12s  %-12s  %s" % (t.get("creationTimestamp", "")[:19], t.get("status", "?"), prog, t.get("name", "?")[:70]))
    for e in (t.get("errors") or [])[:2]:
        msg = e.get("message", e) if isinstance(e, dict) else e
        print("      error: %s" % str(msg)[:100])
'
  fi
  sleep "$EVERY"
done
