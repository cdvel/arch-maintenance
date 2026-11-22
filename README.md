# Arch Linux Maintenance

[![CI](https://github.com/cdvel/arch-maintenance/actions/workflows/ci.yml/badge.svg)](https://github.com/cdvel/arch-maintenance/actions/workflows/ci.yml)

Maintenance for an Arch Linux desktop. Safe tasks run on systemd timers; package upgrades stay interactive.

- **Automated:** update pre-download, Flatpak updates, cache trimming, mirror refresh, TRIM, pacman database snapshots.
- **Notifications:** stale updates, `.pacnew` files, pending reboot, failed units, full disks, AUR packages that changed maintainer or PKGBUILD, known vulnerabilities with a fix available.
- **Interactive:** Arch news, repo and AUR upgrade, `.pacnew` merge, reboot check.

## Quick start

```bash
sudo pacman -S --needed pacman-contrib fakeroot reflector libnotify
git clone https://github.com/cdvel/arch-maintenance.git
cd arch-maintenance
./install.sh            # as your normal user; prompts for sudo
arch-maintenance        # status report
```

Optional: [`yay`](https://github.com/Jguer/yay) for AUR upgrades and Arch news, `flatpak`, `curl` and `jq` for the AUR drift check, [`arch-audit`](https://archlinux.org/packages/extra/x86_64/arch-audit/) for vulnerability advisories.

## Commands

| Command | Action |
|---|---|
| `arch-maintenance` | Status report (read-only, no sudo) |
| `arch-maintenance update` | Guided upgrade |
| `arch-maintenance clean` | Orphan and cache cleanup |
| `arch-maintenance aur baseline` | Record the installed AUR packages' maintainers and PKGBUILD hashes |
| `arch-maintenance aur check` | Report AUR changes since the baseline (exit 1 on drift) |
| `arch-maintenance help` | Commands and settings |

### status

```
==> Updates
  ! Last full upgrade 23 days ago; 412 repo + 3 AUR updates pending

==> AUR packages
  ! example-bin: maintainer changed from alice to mallory
  • other-bin: flagged out of date on the AUR

==> Security advisories
  ! Known vulnerabilities with a fix available in 1 installed package(s)
      ...

==> Config files
  ! 2 .pacnew/.pacsave files to merge (run: arch-maintenance update)
      /etc/pacman.conf.pacnew
      /etc/pacman.d/mirrorlist.pacnew

==> System
  ✓ Running kernel 7.1.4-arch1-1 is current
  ✓ No failed units
  ✓ All filesystems below 90%

==> Caches
  ✓ pacman cache: 3.1G
  ✓ AUR build cache: 2.4G
  ✓ journal: 812M
```

### update

1. Arch news since the last upgrade, with a confirmation prompt
2. AUR drift check, with a confirmation prompt when something changed
3. `yay -Syu`, or `sudo pacman -Syu` without yay
4. AUR baseline refresh
5. Flatpak update, including the GL extension for a new NVIDIA driver
6. `.pacnew`/`.pacsave` merge with `pacdiff`
7. Reboot check

Steps 4–7 are skipped if the upgrade fails or is cancelled.

### clean

1. Orphan removal, after confirmation
2. pacman cache trim: newest 2 versions of installed packages, none of uninstalled
3. AUR build cache cleanup with `yay -Sc`
4. Journal size

Also warns when makepkg's `debug` option is building `*-debug` packages.

### AUR drift

AUR packages run their PKGBUILD as your user, and an orphaned package can be adopted by anyone. `arch-maintenance aur baseline` records, for each installed AUR package, its maintainer, the AUR's last-modified time and a hash of its PKGBUILD. `status` and `update` then compare the AUR against it:

| Finding | Severity |
|---|---|
| Maintainer changed, or an orphan was adopted | Warning, notified |
| A name that was not on the AUR at baseline now is | Warning, notified |
| Orphaned, or removed from the AUR | Warning, notified |
| Same installed and AUR version, but the PKGBUILD hash differs | Warning, notified |
| Flagged out of date | Listed only |

The PKGBUILD is fetched and hashed only for packages whose AUR modification time moved while the version stayed the same, so a normal release is not reported. When an update is pending, the baseline keeps no hash for that package until `update` refreshes it. Split packages such as `*-debug` are tracked under their base.

The first baseline assumes your installed AUR packages are trustworthy today. It detects change, not an existing compromise. `update` refreshes the baseline after an upgrade you confirmed. State is in `~/.local/state/arch-maintenance/aur-baseline.tsv`; AUR responses are cached for 6 hours. Without a baseline, `status` still reports orphans. Set `ARCH_MAINT_AUR_CHECK=0` to turn the check off.

Vulnerability advisories come from `arch-audit -u` (optional) and are listed only for packages that have a fix available.

## Automated tasks

| Task | Schedule |
|---|---|
| Download pending updates to the cache, without installing | daily |
| Flatpak update and unused runtime removal | daily |
| Status check with desktop notification | daily, 10:00 |
| Package cache trim (upstream `paccache.timer`, 2 versions kept) | weekly |
| Mirror refresh (upstream `reflector.timer`) | weekly |
| SSD TRIM (upstream `fstrim.timer`) | weekly |
| pacman database snapshot (10 kept) | before every transaction |
| Journal cap at 1G | always |

Notification triggers: last full upgrade older than 14 days, `.pacnew` files, failed units, pending reboot, filesystem above 90%.

The pre-download uses `checkupdates --download` against a temporary copy of the sync databases. The system package database is not modified, so no partial upgrade is possible.

### Upgrade policy

Upgrades are not automated. An unattended `pacman -Syu --noconfirm` skips:

- **Arch news** announcing upgrades that need manual steps
- **File conflicts** that need an `--overwrite` decision
- **`.pacnew` files** from changed config defaults
- **DKMS builds** (NVIDIA, VirtualBox) that can fail on kernel upgrades
- **AUR PKGBUILDs**, which run as your user

### Flatpak

Flatpak apps bundle their runtimes and have no pacman dependencies, so unattended updates and orphan removal are both safe for them. The exception is the GPU driver: an NVIDIA driver upgrade needs the matching `org.freedesktop.Platform.GL.nvidia-*` extension, which `update` installs after the system upgrade.

## Configuration

### Installer options

| Option | Effect |
|---|---|
| `./install.sh --no-journald` | Skip the 1G journal cap |
| `./install.sh --uninstall` | Remove all installed files |

Uninstall keeps the upstream `paccache`, `reflector` and `fstrim` timers enabled, and keeps database snapshots.

Mirror selection: `/etc/xdg/reflector/reflector.conf`.

### Environment variables

| Variable | Default | Effect |
|---|---|---|
| `ARCH_MAINT_MAX_AGE_DAYS` | 14 | Days before a stale upgrade is flagged |
| `ARCH_MAINT_DISK_WARN_PCT` | 90 | Disk usage warning threshold |
| `ARCH_MAINT_CACHE_KEEP` | 2 | Package versions `clean` keeps in the cache |
| `ARCH_MAINT_AUR_CHECK` | 1 | Set to 0 to turn off the AUR drift check |
| `DIFFPROG` | `vim -d` | Merge tool for `pacdiff` |

## Reference

### Timer status

```bash
systemctl list-timers paccache.timer reflector.timer fstrim.timer pacman-predownload.timer flatpak-update.timer
systemctl --user list-timers arch-status.timer
journalctl -u pacman-predownload -u flatpak-update -u paccache
```

### Database restore

```bash
ls /var/lib/pacman/backup/
sudo tar --zstd -xf /var/lib/pacman/backup/local-<stamp>.tar.zst -C /var/lib/pacman
```

### Installed files

| Path | Purpose |
|---|---|
| `/usr/local/bin/arch-maintenance` | Command |
| `/usr/local/lib/arch-maintenance/pacman-db-backup` | Database snapshot script |
| `/etc/pacman.d/hooks/00-arch-maintenance-db-backup.hook` | Snapshot trigger before each transaction |
| `/etc/systemd/system/pacman-predownload.{service,timer}` | Update pre-download |
| `/etc/systemd/system/flatpak-update.{service,timer}` | Flatpak updates (if Flatpak is installed) |
| `/etc/systemd/system/paccache.service.d/arch-maintenance.conf` | Cache retention for `paccache.timer` |
| `/etc/systemd/user/arch-status.{service,timer}` | Daily status notification |
| `/etc/systemd/journald.conf.d/arch-maintenance.conf` | Journal size cap |

### Migration from v1

`./install.sh` removes the v1 `arch-maintenance.service`, `arch-maintenance.timer` and logrotate config. Changes are listed in [CHANGELOG.md](CHANGELOG.md).

### Agent prompt

[PROMPT.md](PROMPT.md): a coding-agent prompt (e.g. Claude Code) for installation and a full maintenance run, with sudo and interactive steps left to you.

## Testing

**CI:** shellcheck, `systemd-analyze verify` on all units, a pacman transaction exercising the snapshot hook and rotation, offline tests of the AUR drift check (`test/aur-drift.sh`, fixtures stand in for pacman and the AUR), and CLI smoke tests, in an `archlinux` container on every push to `main` and every pull request.

**Integration test:** `test/nspawn.sh` boots systemd in a throwaway `systemd-nspawn` container built from an [Arch Linux Archive](https://archive.archlinux.org/) snapshot, so pending updates are real. The container lives under `/var/tmp` and is deleted on exit, including on failure or Ctrl-C.

```bash
sudo pacman -S --needed arch-install-scripts
sudo test/nspawn.sh run                    # install, hook, timers, services, status, uninstall
sudo test/nspawn.sh run --skip-download    # without the update pre-download check
sudo test/nspawn.sh run --date 2026/06/01  # archive snapshot date (default: 90 days ago)
sudo test/nspawn.sh shell                  # interactive session for update and clean
```

Each run downloads about 500MB. Kernel upgrades, DKMS and the reboot check are not covered (the container shares the host kernel).

## License

[MIT](LICENSE)

## Credits

Based on [Fernando Cejas's Arch Linux system maintenance guide](https://fernandocejas.com/blog/engineering/2022-03-30-arch-linux-system-maintance/) and the [Arch Wiki system maintenance page](https://wiki.archlinux.org/title/System_maintenance).
