#!/usr/bin/env bash
# vsp-watch.sh: watch the VCF services runtime (VSP) Kubernetes cluster settle.
#
# The VCF management services (fleet lifecycle, depot, identity broker, Salt and
# so on) run as pods on VSP. After a patch, pods reconcile in their own time;
# this shows that happening so you trust the cluster, not a lagging UI.
# Read-only: it only runs kubectl get/logs.
#
# Run it ON a VSP control-plane node (VCF 9.1 docs, "Establish an SSH
# Connection to a VCF Services Runtime Instance"):
#   ssh vmware-system-user@<control-plane-ip>     # APPLIANCE_ROOT_PASSWORD
#     (take the IP from VCF Ops > Build > Lifecycle > VCF Management >
#      Components > VCF services runtime > Nodes; the runtime FQDN can be a worker)
#   sudo -i
#   bash /tmp/vsp-watch.sh                         # uses admin.conf or ~/.kube/config
#
#   bash vsp-watch.sh                  refresh every 15 s (Ctrl+C to stop)
#   bash vsp-watch.sh --every 30
#   bash vsp-watch.sh --once          one snapshot, then exit
#   bash vsp-watch.sh --namespaces     list namespaces with pod counts
#   bash vsp-watch.sh --logs <ns> [pod-prefix]   follow logs in a namespace
set -uo pipefail
# Control-plane nodes have admin.conf (VCF 9.1 docs); otherwise use root's ~/.kube/config.
if [ -z "${KUBECONFIG:-}" ] && [ -r /etc/kubernetes/admin.conf ]; then export KUBECONFIG=/etc/kubernetes/admin.conf; fi
EVERY=15
ONCE=no

case "${1:-}" in
  -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
  --every) EVERY="${2:-15}" ;;
  --once) ONCE=yes ;;
  --namespaces)
    kubectl get pods -A --no-headers 2>/dev/null | awk '{n[$1]++; if ($4!="Running" && $4!="Completed") b[$1]++} END {for (k in n) printf "%-40s %4d pods  %3d not ready\n", k, n[k], b[k]+0}' | sort
    exit 0 ;;
  --logs)
    ns="${2:?namespace required}"; prefix="${3:-}"
    pods=$(kubectl -n "$ns" get pods --no-headers -o custom-columns=:metadata.name | grep -E "^${prefix}" || true)
    [ -n "$pods" ] || { echo "no pods in $ns matching '${prefix}'"; exit 1; }
    echo "following: $pods  (Ctrl+C to stop)"
    trap 'kill 0' INT TERM
    for p in $pods; do
      kubectl -n "$ns" logs -f --all-containers --prefix --timestamps --since=10m "pod/$p" 2>&1 &
    done
    wait
    exit 0 ;;
esac

while :; do
  [ "$ONCE" = yes ] || clear
  echo "VSP cluster  $(date '+%F %T')  (every ${EVERY}s, Ctrl+C to stop)"
  echo; echo "== nodes"
  kubectl get nodes -o wide 2>&1 | awk '{print $1, $2, $3, $5, $6}' | column -t
  total=$(kubectl get pods -A --no-headers 2>/dev/null | wc -l)
  echo; echo "== pods not Running/Completed (of $total)"
  kubectl get pods -A --no-headers 2>/dev/null | awk '$4!="Running" && $4!="Completed" {print $1, $2, $3, $4, $5, $6}' | column -t | head -25
  echo; echo "== pods with restarts (top 10)"
  kubectl get pods -A --no-headers 2>/dev/null | awk '$5+0>0 {print $5, $1, $2}' | sort -rn | head -10 | column -t
  echo; echo "== last warning events"
  kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp 2>/dev/null | tail -8 | cut -c1-180
  [ "$ONCE" = yes ] && break
  sleep "$EVERY"
done
