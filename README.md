# vcf-lab-scripts

Scripts for VMware Cloud Foundation hands-on labs. Fetch a script from inside the lab, read it, then run it. Nothing here holds a password, token or hostname: anything secret is typed at the console when the script asks.

## backup/sftp-backup-target.sh

Turns an Ubuntu VM into an SFTP backup target for SDDC Manager and the VCF fleet, vCenter (VAMI file-based backup) and NSX Manager.

```sh
curl -fsSLO https://raw.githubusercontent.com/peteha/vcf-lab-scripts/main/backup/sftp-backup-target.sh
less sftp-backup-target.sh                  # read it first
sudo bash sftp-backup-target.sh --check     # read-only: what is there now
sudo bash sftp-backup-target.sh --apply     # creates the user, folders and sshd drop-in; asks for the password
sudo bash sftp-backup-target.sh --list      # after backups run: what landed, with sizes
```

`--apply` creates:
- an SFTP-only user, `vcfbackup`. It has no shell, is chrooted to `/backups`, and its password is typed at the `passwd` prompt;
- one folder per backup source: `sddc-fleet`, `vcenter-mgmt`, `vcenter-wld01`, `nsx-mgmt`, `nsx-wld01`;
- an sshd drop-in at `/etc/ssh/sshd_config.d/50-vcf-sftp-backup.conf`. It is checked with `sshd -t` before ssh restarts, and removed again if the check fails.

It then prints the server address, port, user, the folder for each product, and the host key fingerprints (SHA256) to check when each product asks you to accept the server.

Options: `--user`, `--root`, `--folders "a b c"`. Re-running `--apply` is safe.

## Licence

MIT
