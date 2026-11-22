# Ansible Role: logrotate

![GitHub](https://img.shields.io/github/license/jomrr/ansible-role-logrotate)
![GitHub last commit](https://img.shields.io/github/last-commit/jomrr/ansible-role-logrotate)
![GitHub issues](https://img.shields.io/github/issues-raw/jomrr/ansible-role-logrotate)
[![dev](https://img.shields.io/github/actions/workflow/status/jomrr/ansible-role-logrotate/dev.yml?branch=dev&label=dev)](https://github.com/jomrr/ansible-role-logrotate/actions/workflows/dev.yml?query=branch%3Adev)
[![main](https://img.shields.io/github/actions/workflow/status/jomrr/ansible-role-logrotate/main.yml?branch=main&label=main)](https://github.com/jomrr/ansible-role-logrotate/actions/workflows/main.yml?query=branch%3Amain)

Rotate and compress application and web server logs on systemd hosts.

## Purpose

Install logrotate and enable its systemd timer. Rotate nonempty file logs daily,
retain archives by age and compress them one rotation later. Repeated runs with
the same policy are idempotent. Package rules can override individual defaults.

## Dependencies

```yaml
collections:
  - name: community.general
    version: '>=12.0.0'
  - name: ansible.posix
    version: '>=2.0.0'
```

## Role Variables

### `logrotate_retention_days`

Type: `int`. Required: `false`.

Positive archive age in days. Expiry is evaluated when the corresponding active
log rotates.

Default:

```yaml
logrotate_retention_days: 90
```

### `logrotate_max_size_mib`

Type: `int`. Required: `false`.

Positive size threshold in MiB for managed web and application logs. A timer
check rotates a larger log before its daily rotation.

Default:

```yaml
logrotate_max_size_mib: 100
```

### `logrotate_check_interval_minutes`

Type: `int`. Required: `false`.

Interval in minutes between logrotate checks.

Default:

```yaml
logrotate_check_interval_minutes: 60
```

### `logrotate_web_servers`

Type: `list`. Required: `false`.

Adopt the standard package rotation file for each selected, installed web
server. Run the role after installing the web servers.
An empty list skips adoption. Restore the distribution file when handing a
previously adopted server back to its package.

Default:

```yaml
logrotate_web_servers: []
```

### `logrotate_rules`

Type: `list`. Required: `false`.

Named files under /etc/logrotate.d. Unlisted files are retained. Set state to
absent to remove a file.
Each rule accepts an absolute path or filename glob, optional retention and size
limits, a rotation account and a service to reload.

Default:

```yaml
logrotate_rules: []
```

## Managed Files

- `/etc/logrotate.d/00-ansible-policy` Sets defaults for subsequent rules.
- `/etc/logrotate.d/<name>` One file per entry in logrotate_rules. Unlisted
  files are retained. Use state=absent to remove a rule.
- `/etc/logrotate.d/nginx` Adopted when nginx is installed and selected.
- `/etc/logrotate.d/apache2 or /etc/logrotate.d/httpd` Adopted for the selected
  Apache package, including an administrator override on openSUSE.
- `/etc/systemd/system/logrotate.timer.d/50-schedule.conf` Sets a persistent
  timer with up to one minute of randomized delay.

## Check Mode

Check mode previews package, rule and timer changes on a configured host. The
complete configuration check reads the files currently on disk. First
installation requires the package-provided directory and timer.

## Service Behavior

A schedule change reloads systemd and restarts the timer. Each run restores a
stopped or disabled timer. Logrotate reads the configuration on each invocation.
Rotation signals the active nginx master with USR1 or gracefully reloads Apache.
Managed web profiles create the replacement log with mode 0640. Debian-family
web profiles also run the distribution's httpd-prerotate hooks.

## Security Notes

- CIS Controls v8.1 Safeguard 8.10 calls for at least 90 days for audit logs.
  This role applies that period as a default for file logs. Journald, auditd and
  a central archive have their own retention policies.
- DISA Apache 2.4 UNIX STIG AS24-U1-000710 requires capacity sized for the
  workload. The 100 MiB threshold and hourly checks are operational defaults.
  They are adjustable independently of retention.
- `su_user` and `su_group` are required when the log directory is writable by a
  non-root user. Choose an account that can rename and recreate the file. Only
  administrators should be able to edit rotation rules and service units.
- Fedora ships /var/log/nginx as root:root with mode 0711. Only root can rename
  or create entries there. The openSUSE nginx profile uses `su nginx nginx` for
  its nginx-owned directory. For web profiles that rotate as root, the role
  checks directory ownership and write bits before adoption.

## Operational Notes

- The global drop-in sets `daily`, `rotate -1`, `maxage 90` by default,
  `compress`, `delaycompress`, `notifempty`, `dateext` with `dateformat
  -%Y%m%d-%s`, and `create` with the original owner, group and mode. The suffix
  combines a calendar date and Unix time in seconds, including during the
  repeated hour when daylight saving time ends.
- Managed application and web stanzas set their own daily schedule, age policy,
  archive naming and compression. They add `missingok` and `maxsize`. Web rules
  also set `sharedscripts` and `create 0640`. Application rules with reopen=none
  need a writer that closes and reopens the log itself. With reopen=reload,
  service names the systemd unit to reload once after rotation. With
  reopen=copytruncate, the writer keeps the same inode. Records written between
  copying and truncation can be lost.
- Each changed fragment is checked before installation. After writing the rules
  and before enabling or restarting the timer, the role checks the complete
  installed configuration with `logrotate --debug` on every run. A duplicate log
  entry across files fails convergence. Debug mode preserves log files and the
  state file. On openSUSE, the check follows the package's choice of main
  configuration and gives local drop-ins precedence over vendor files with the
  same relative name.
- The role changes the system-wide logrotate.timer. Logrotate uses its
  persistent state file to keep daily rules on their daily schedule even when
  the timer checks more frequently.
- By default the timer checks hourly. A selected web or application log larger
  than 100 MiB rotates at the next check. During a traffic burst it can grow by
  another check interval's worth of writes. For example, 500 requests/s at 400
  logged bytes per request adds about 687 MiB per hour. Measure access and error
  logs separately and choose a shorter interval for busy hosts.
- Size storage from observed compressed bytes per day times the retention
  period, then add room for active files, the latest uncompressed rotation and
  peak traffic. Monitor free space and forward logs off-host when retention is
  mandatory.
- The 90-day default uses maxage and an unlimited archive count. Multiple
  rotations per day can coexist. Logrotate checks archive age only when the
  active log rotates. With `notifempty`, an empty log or a retired virtual host
  can leave archives past the configured age. Include those archives in the
  site's decommissioning procedure. After switching naming or compression
  schemes, review archives under the old names separately.
- The distribution's main configuration must load its drop-in directory. The
  openSUSE package uses logrotate-all for this. Other package rules can set
  their own count, age, file mode or interval. Keep application globs narrow
  enough to exclude archives and paths owned by other rules.
- Web server adoption is opt-in. It replaces the standard package rule at the
  same pathname. Review custom hooks and paths before enabling it. Debian and
  Red Hat family hosts keep module-generated backups. On openSUSE the package
  runner explicitly passes every file in its drop-in directories to logrotate.
  Keep backups outside these directories.

## Supported Platforms

| OS Family | Distribution | Version | Container Image |
| --------- | ------------ | ------- | --------------- |
| RedHat | AlmaLinux | latest | [jomrr/molecule-almalinux:latest](https://hub.docker.com/r/jomrr/molecule-almalinux) |
| Debian | Debian | latest | [jomrr/molecule-debian:latest](https://hub.docker.com/r/jomrr/molecule-debian) |
| RedHat | Fedora | latest | [jomrr/molecule-fedora:latest](https://hub.docker.com/r/jomrr/molecule-fedora) |
| Suse | OpenSuse Leap | latest | [jomrr/molecule-opensuse-leap:latest](https://hub.docker.com/r/jomrr/molecule-opensuse-leap) |
| Suse | OpenSuse Tumbleweed | latest | [jomrr/molecule-opensuse-tumbleweed:latest](https://hub.docker.com/r/jomrr/molecule-opensuse-tumbleweed) |
| Debian | Ubuntu | latest | [jomrr/molecule-ubuntu:latest](https://hub.docker.com/r/jomrr/molecule-ubuntu) |

## Example Playbook

### Select the web profile for nginx hosts

Store this setting in `group_vars/nginx/logrotate.yml`.

```yaml
---
logrotate_web_servers: [nginx]
```

### Apply the system-wide defaults

```yaml
---
- name: Configure log rotation
  hosts: webservers
  gather_facts: true
  roles:
    - role: jomrr.logrotate
```

### Check busy servers every 15 minutes

```yaml
---
- name: Configure rotation for the web tier and its application
  hosts: webservers
  gather_facts: true
  roles:
    - role: jomrr.logrotate
      logrotate_web_servers: [nginx]
      logrotate_check_interval_minutes: 15
      logrotate_max_size_mib: 100
      logrotate_rules:
        - name: orders
          path: /var/log/orders/*.log
          retention_days: 180
          max_size_mib: 50
          su_user: orders
          su_group: orders
          reopen: reload
          service: orders.service
        - name: legacy-exporter
          path: /var/log/legacy-exporter/output.log
          reopen: copytruncate
        - name: retired-app
          state: absent
```

## References

- [logrotate manual](https://github.com/logrotate/logrotate/blob/main/logrotate.8.in)
- [CIS Controls v8.1, Safeguard 8.10](https://www.cisecurity.org/controls/cis-controls-navigator)
- [DISA Apache 2.4 UNIX STIG, AS24-U1-000710](https://ncp.nist.gov/checklist/917)
- [nginx log reopening](https://nginx.org/en/docs/control.html#logs)
- [Apache log rotation](https://httpd.apache.org/docs/2.4/logs.html#rotation)

## Author

[Jonas Mauer](https://github.com/jomrr)

## License

This project is licensed under the MIT License.
See [LICENSE](LICENSE) for the full license text.

Copyright (c) 2026 Jonas Mauer.
