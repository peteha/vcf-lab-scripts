#!/usr/bin/env bash
# sftp-backup-target.sh: turn an Ubuntu VM into an SFTP backup target for VCF.
#
# Targets SDDC Manager / the VCF fleet, vCenter (VAMI file-based backup) and
# NSX Manager. It makes one SFTP-only, chrooted user and one folder per backup
# source, and prints what to type into each product.
#
#   sudo bash sftp-backup-target.sh --check    read-only: what is here now (the default)
#   sudo bash sftp-backup-target.sh --apply    create user, folders, sshd drop-in
#   sudo bash sftp-backup-target.sh --list     show the backups that have landed
#
# Options, with defaults:
#   --user vcfbackup
#   --root /backups
#   --folders "fleet sddc-nsx vcenter-mgmt vcenter-wld01"
#
# Folders: SDDC Manager sets the NSX backup target too, so NSX shares
# sddc-nsx. fleet is the fleet/Automation backup; one per vCenter.
#
# Password: the hosted VCF lab's standard password, VMware123!VMware123!, is
# set through chpasswd on stdin, so it never appears on a command line or in
# the process list. Use --prompt to type your own at the passwd prompt
# instead. Re-running --apply is safe: it skips what exists, and leaves an
# existing password alone.
#
# sudo: run it as a normal user and it re-runs itself under sudo, giving sudo
# the same lab standard password on stdin, so nothing is typed. The same
# password is the backup encryption passphrase to use in each product.
set -euo pipefail

SELF="$(readlink -f "$0")"
ARGS=("$@")
MODE=check
USER_NAME=vcfbackup
ROOT=/backups
FOLDERS="fleet sddc-nsx vcenter-mgmt vcenter-wld01"
LAB_PASSWORD='VMware123!VMware123!'
PROMPT=no
DROPIN=/etc/ssh/sshd_config.d/50-vcf-sftp-backup.conf

while [ $# -gt 0 ]; do
  case "$1" in
    --check) MODE=check ;;
    --apply) MODE=apply ;;
    --list)  MODE=list ;;
    --prompt) PROMPT=yes ;;
    --user) USER_NAME="$2"; shift ;;
    --root) ROOT="$2"; shift ;;
    --folders) FOLDERS="$2"; shift ;;
    -h|--help) sed -n '2,31p' "$0"; exit 0 ;;
    *) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

say()  { printf '\n== %s\n' "$*"; }
ok()   { printf '  ok    %s\n' "$*"; }
todo() { printf '  todo  %s\n' "$*"; }
warn() { printf '  warn  %s\n' "$*"; }

# Re-run under sudo with the lab standard password on stdin (never in argv).
elevate() {
  [ "$(id -u)" -eq 0 ] && return 0
  printf '%s\n' "$LAB_PASSWORD" | exec sudo -S -p '' bash "$SELF" "${ARGS[@]}"
}
need_root() { [ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }; }

primary_ip() { ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}'; }

fingerprints() {
  for t in ecdsa ed25519 rsa; do
    f=/etc/ssh/ssh_host_${t}_key.pub
    [ -f "$f" ] || continue
    printf '  %-8s %s\n' "$t" "$(ssh-keygen -lf "$f" -E sha256 | awk '{print $2}')"
  done
}

check() {
  say "host"
  . /etc/os-release 2>/dev/null && ok "$PRETTY_NAME"
  ok "address $(primary_ip || echo '?')"
  ok "free space under $(dirname "$ROOT"): $(df -h "$(dirname "$ROOT")" | awk 'NR==2{print $4}')"
  say "ssh"
  if command -v sshd >/dev/null; then ok "openssh-server installed"; else todo "openssh-server not installed (--apply installs it)"; fi
  if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then ok "ssh running"; else todo "ssh not running"; fi
  [ -f "$DROPIN" ] && ok "drop-in present: $DROPIN" || todo "drop-in missing: $DROPIN"
  say "backup user and folders"
  if id "$USER_NAME" >/dev/null 2>&1; then ok "user $USER_NAME exists"; else todo "user $USER_NAME missing"; fi
  if [ -d "$ROOT" ]; then
    o=$(stat -c '%U:%a' "$ROOT"); [ "$o" = "root:755" ] && ok "$ROOT root:755 (chroot-safe)" || warn "$ROOT is $o, chroot needs root:755"
    for d in $FOLDERS; do [ -d "$ROOT/$d" ] && ok "$ROOT/$d" || todo "$ROOT/$d missing"; done
  else
    todo "$ROOT missing"
  fi
  say "host key fingerprints (SHA256), to confirm when the products ask"
  fingerprints || true
}

apply() {
  need_root
  say "packages"
  if ! command -v sshd >/dev/null; then apt-get update -qq && apt-get install -y -qq openssh-server; fi
  ok "openssh-server"

  say "user"
  if ! id "$USER_NAME" >/dev/null 2>&1; then
    useradd --no-create-home --home-dir / --shell /usr/sbin/nologin "$USER_NAME"
    ok "created $USER_NAME (no shell)"
  else
    ok "$USER_NAME exists"
  fi
  if passwd -S "$USER_NAME" | awk '{exit !($2=="P")}'; then
    ok "password already set (not changed)"
  else
    if [ "$PROMPT" = yes ]; then
      echo "  Set the password for $USER_NAME now. Type it here; it is not shown or logged."
      passwd "$USER_NAME"
    else
      printf '%s:%s\n' "$USER_NAME" "$LAB_PASSWORD" | chpasswd
      ok "password set to the lab standard password (through chpasswd on stdin)"
    fi
  fi

  say "folders"
  install -d -o root -g root -m 755 "$ROOT"
  for d in $FOLDERS; do
    install -d -o "$USER_NAME" -g "$USER_NAME" -m 750 "$ROOT/$d"
    ok "$ROOT/$d"
  done

  say "sshd: SFTP-only and chrooted for $USER_NAME"
  cat > "$DROPIN.new" <<EOF
# Written by sftp-backup-target.sh: SFTP-only, chrooted backup user for VCF.
Match User $USER_NAME
    ChrootDirectory $ROOT
    ForceCommand internal-sftp
    PasswordAuthentication yes
    AllowTcpForwarding no
    X11Forwarding no
    PermitTunnel no
EOF
  mv "$DROPIN.new" "$DROPIN"
  if sshd -t; then
    systemctl restart ssh 2>/dev/null || systemctl restart sshd
    ok "drop-in valid, ssh restarted"
  else
    rm -f "$DROPIN"; echo "sshd -t failed; drop-in removed, ssh unchanged" >&2; exit 1
  fi

  say "enter these in each product"
  ip=$(primary_ip || echo '<this VM address>')
  printf '  server     %s   port 22   protocol SFTP\n' "$ip"
  printf '  user       %s   password: the lab standard password (or yours, with --prompt)\n' "$USER_NAME"
  printf '  encryption passphrase: the lab standard password (it is needed to restore)\n'
  printf '  directory  /<folder>, relative to the chroot:\n'
  for d in $FOLDERS; do printf '               /%s\n' "$d"; done
  printf '  fingerprint (SHA256):\n'; fingerprints
  echo
  echo "  Each product shows the server's fingerprint when you add it. Check it against the list above before accepting."
}

list() {
  need_root
  say "backups under $ROOT"
  for d in $FOLDERS; do
    [ -d "$ROOT/$d" ] || { todo "$ROOT/$d missing"; continue; }
    n=$(find "$ROOT/$d" -type f | wc -l)
    s=$(du -sh "$ROOT/$d" | awk '{print $1}')
    printf '\n  /%s   %s files, %s\n' "$d" "$n" "$s"
    find "$ROOT/$d" -type f -printf '    %TY-%Tm-%Td %TH:%TM  %10s  %P\n' | sort | tail -n 15
  done
}

case "$MODE" in apply|list) elevate ;; esac

case "$MODE" in
  check) check ;;
  apply) apply ;;
  list)  list ;;
esac
