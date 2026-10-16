# Arch Linux Maintenance

Routine upkeep for an Arch Linux desktop, split by what is safe to automate:

- **Unattended**: work that cannot break the system runs on systemd timers and a pacman hook.
- **Interactive**: package upgrades, which on Arch need a person present, run through one command that walks you through each step.

## Why upgrades aren't automated

Arch is a rolling release, and an unattended `pacman -Syu --noconfirm` skips the steps that keep it healthy:

- **Arch news** sometimes announces upgrades that require manual intervention before or after.
- **File conflicts** stop the transaction and need a decision (`--overwrite` or not).
- **`.pacnew` files** pile up when config defaults change, and stale configs cause subtle breakage.
- **DKMS modules** (NVIDIA, VirtualBox) rebuild on kernel upgrades; a failed build should be seen before rebooting.
- **AUR packages** are build scripts that run as you; each update deserves a glance.

So the automation does everything around the upgrade (pre-downloading packages, trimming caches, snapshotting the package database, notifying you) and leaves the upgrade itself to you.

## What runs where

| Unattended | Schedule |
|---|---|
| Pre-download pending repo updates (`checkupdates --download`, never touches the system DB) | daily |
| Flatpak update and unused runtime removal | daily |
| Status check with desktop notification when something needs attention | daily, 10:00 |
| Package cache trim: keep 2 versions of installed packages, drop uninstalled (`paccache.timer`) | weekly |
| Mirror list refresh (`reflector.timer`, uses `/etc/xdg/reflector/reflector.conf`) | weekly |
| SSD TRIM (`fstrim.timer`) | weekly |
| Pacman database snapshot, newest 10 kept | before every pacman transaction |
| Journal capped at 1G (`SystemMaxUse`) | continuous |

| Interactive | Command |
|---|---|
| Health report: update age, pending updates, `.pacnew` files, reboot needed, failed units, disk usage, cache sizes | `arch-maintenance` |
| Arch news, full upgrade (repo + AUR), Flatpak update, `.pacnew` merge, reboot check | `arch-maintenance update` |
| Orphan review, pacman and AUR cache cleanup | `arch-maintenance clean` |

The status notification fires when the last full upgrade is older than 14 days, or when there are `.pacnew` files, failed units, a pending reboot, or a filesystem above 90%.

## Requirements

- `pacman-contrib` (`paccache`, `checkupdates`, `pacdiff`)
- `reflector`
- `libnotify` (`notify-send`)
- Optional: [`yay`](https://github.com/Jguer/yay) for AUR upgrades and Arch news, `flatpak`

```bash
sudo pacman -S --needed pacman-contrib reflector libnotify
```

## Installation

Run as your normal user (not with sudo); the script asks for sudo where needed and enables the status timer for your user.

```bash
git clone https://github.com/cdvel/arch-maintenance.git
cd arch-maintenance
./install.sh
```

Options:

- `--no-journald` skips the 1G journal cap.
- `--uninstall` removes everything the installer added. The upstream `paccache`, `reflector` and `fstrim` timers stay enabled, and database snapshots are kept.

Installing over v1 removes the old `arch-maintenance.service`/`.timer` and logrotate config if present.

### Installed files

| Path | Purpose |
|---|---|
| `/usr/local/bin/arch-maintenance` | Interactive command |
| `/usr/local/lib/arch-maintenance/pacman-db-backup` | Snapshot script |
| `/etc/pacman.d/hooks/00-arch-maintenance-db-backup.hook` | Runs the snapshot before each transaction |
| `/etc/systemd/system/pacman-predownload.{service,timer}` | Update pre-download |
| `/etc/systemd/system/flatpak-update.{service,timer}` | Flatpak updates (only if Flatpak is installed) |
| `/etc/systemd/system/paccache.service.d/arch-maintenance.conf` | Cache retention policy for the upstream `paccache.timer` |
| `/etc/systemd/user/arch-status.{service,timer}` | Daily status notification |
| `/etc/systemd/journald.conf.d/arch-maintenance.conf` | Journal size cap |

## Usage

```bash
arch-maintenance            # status report
arch-maintenance update     # upgrade walkthrough
arch-maintenance clean      # orphans and caches
```

Tunables (environment variables):

| Variable | Default | Effect |
|---|---|---|
| `ARCH_MAINT_MAX_AGE_DAYS` | 14 | Days before a stale upgrade is flagged |
| `ARCH_MAINT_DISK_WARN_PCT` | 90 | Disk usage warning threshold |
| `ARCH_MAINT_CACHE_KEEP` | 2 | Package versions `clean` keeps in the cache |
| `DIFFPROG` | `vim -d` | Merge tool used by `pacdiff` |

### Agent-assisted run

[PROMPT.md](PROMPT.md) has a prompt for a coding agent (e.g. Claude Code) that walks through installation and a full maintenance run, with you running the sudo and interactive steps.

### Flatpak

Flatpak apps ship their own runtimes and don't depend on pacman packages, so removing orphans can't break them and they update safely unattended. The one link to the host is the GPU driver: after an NVIDIA driver upgrade, Flatpak needs the matching `org.freedesktop.Platform.GL.nvidia-*` extension. `arch-maintenance update` runs a Flatpak update right after the system upgrade to pick it up.

### Restoring the pacman database

```bash
ls /var/lib/pacman/backup/
sudo tar --zstd -xf /var/lib/pacman/backup/local-<stamp>.tar.zst -C /var/lib/pacman
```

### Checking the timers

```bash
systemctl list-timers paccache.timer reflector.timer fstrim.timer pacman-predownload.timer flatpak-update.timer
systemctl --user list-timers arch-status.timer
journalctl -u pacman-predownload -u flatpak-update -u paccache
```

## License

[MIT License](LICENSE)

## Credits

Originally based on [Fernando Cejas's Arch Linux system maintenance guide](https://fernandocejas.com/blog/engineering/2022-03-30-arch-linux-system-maintance/), and the [Arch Wiki system maintenance page](https://wiki.archlinux.org/title/System_maintenance).
