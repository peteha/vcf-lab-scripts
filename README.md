# vcf-lab-scripts

Scripts for VMware Cloud Foundation hands-on labs. Fetch a script from inside the lab, read it, then run it. These are for disposable, hosted VCF labs. Where a script sets a password, it uses the lab's standard password, VMware123!VMware123!, unless you ask to type your own. Never run them against a production estate.

## backup/sftp-backup-target.sh

Turns an Ubuntu VM into an SFTP backup target for SDDC Manager and the VCF fleet, vCenter (VAMI file-based backup) and NSX Manager.

```sh
curl -fsSLO https://raw.githubusercontent.com/peteha/vcf-lab-scripts/main/backup/sftp-backup-target.sh
less sftp-backup-target.sh                  # read it first
bash sftp-backup-target.sh --check          # read-only: what is there now
bash sftp-backup-target.sh --apply          # re-runs itself under sudo; creates the user, folders and sshd drop-in
bash sftp-backup-target.sh --list           # after backups run: what landed, with sizes
```

`--apply` creates:
- an SFTP-only user, `vcfbackup`. It has no shell, is chrooted to `/backups`, and its password is the lab standard password, `VMware123!VMware123!`, set through `chpasswd` on stdin. Add `--prompt` to type your own;
- one folder per backup source: `fleet` (fleet and Automation), `sddc-nsx` (SDDC Manager, which also sets NSX's target), `vcenter-mgmt`, `vcenter-wld01`;
- an sshd drop-in at `/etc/ssh/sshd_config.d/50-vcf-sftp-backup.conf`. It is checked with `sshd -t` before ssh restarts, and removed again if the check fails.

It then prints the server address, port, user, the folder for each product, and the host key fingerprints (SHA256) to check when each product asks you to accept the server.

Options: `--user`, `--root`, `--folders "a b c"`, `--prompt`. Re-running `--apply` is safe.

## Licence

MIT
