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

## watch/

Read-only screens for a long upgrade. Each runs in a Terminal on the lab desktop, so one screenshot shows the state without clicking through the UI.

- `workload-watch.sh <ip> ... [--http URL]`: pings (and optionally GETs) workloads every second and logs each probe. Ctrl+C prints the loss summary: the evidence that a management domain upgrade did not touch the workloads.
- `task-watch.sh --host <sddc-manager-fqdn>`: SDDC Manager's running tasks, with step counts, refreshed every 30 s. It uses the lab standard password through stdin, or `--prompt`.

```sh
curl -fsSLO https://raw.githubusercontent.com/peteha/vcf-lab-scripts/main/watch/workload-watch.sh
curl -fsSLO https://raw.githubusercontent.com/peteha/vcf-lab-scripts/main/watch/task-watch.sh
```

## postman/

`vcf-fleet-lcm-readonly.postman_collection.json`: read-only checks against the VCF 9.1 fleet lifecycle API, following the documented token flow. Import it in Postman with **Import > Link**:

```
https://raw.githubusercontent.com/peteha/vcf-lab-scripts/main/postman/vcf-fleet-lcm-readonly.postman_collection.json
```

Turn off SSL certificate verification (Settings > General) for lab certificates, then run requests 1 to 3 in order: they find the fleet lifecycle service, get a VCF Operations token, and exchange it for a fleet lifecycle JWT. Requests 4 to 7 list components, component detail, backups and a task's status. Nothing in it starts a backup or a restore.

## vsp/

`vsp-watch.sh`: watch the VCF services runtime (VSP) Kubernetes cluster settle after a patch: nodes, pods not Running, restarts and recent warning events, refreshed every 15 s. `--namespaces` lists namespaces with pod counts; `--logs <ns> [pod-prefix]` follows logs. Read-only. Run it on a VSP control-plane node as root (`ssh vmware-system-user@<control-plane-ip>` from VCF Ops > VCF services runtime > Nodes; the runtime FQDN can land on a worker, then `sudo -i`), per the VCF 9.1 docs. Copy it from the lab desktop with `scp vsp-watch.sh vmware-system-user@<node>:/tmp/`.
