# Arch Linux Maintenance

[![CI](https://github.com/cdvel/arch-maintenance/actions/workflows/ci.yml/badge.svg)](https://github.com/cdvel/arch-maintenance/actions/workflows/ci.yml)

Keeps an Arch Linux desktop healthy without automating the parts that can break it.

- **Runs on its own:** pre-downloads updates, updates Flatpak apps, trims package caches, refreshes mirrors, runs TRIM, and snapshots the pacman database before every transaction.
- **Tells you when to act:** a daily desktop notification when updates are stale, `.pacnew` files need merging, a reboot is pending, a service failed, or a disk is filling up.
- **Walks you through the rest:** one command shows Arch news, upgrades repo and AUR packages, merges `.pacnew` files and checks whether to reboot.

## Quick start

```bash
sudo pacman -S --needed pacman-contrib fakeroot reflector libnotify
git clone https://github.com/cdvel/arch-maintenance.git
cd arch-maintenance
./install.sh            # as your normal user; asks for sudo when needed
arch-maintenance        # see where your system stands
```

[`yay`](https://github.com/Jguer/yay) and `flatpak` are optional. With yay, upgrades include AUR packages and show Arch news first.

## Usage

| Command | What it does |
|---|---|
| `arch-maintenance` | Status report (read-only, no sudo) |
| `arch-maintenance update` | Upgrade walkthrough |
| `arch-maintenance clean` | Orphan review and cache cleanup |
| `arch-maintenance help` | All commands and settings |

### `arch-maintenance` (status)

```
==> Updates
  ! Last full upgrade 23 days ago; 412 repo + 3 AUR updates pending

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

### `arch-maintenance update`

1. Shows Arch news posted since your last upgrade and waits for you to confirm any manual steps.
2. Runs `yay -Syu` (or `sudo pacman -Syu` without yay). You answer pacman's prompts as usual.
3. Updates Flatpak apps, which also installs the GL extension matching a new NVIDIA driver.
4. Lists `.pacnew`/`.pacsave` files and offers to merge them with `pacdiff`.
5. Tells you if the kernel was upgraded and a reboot is needed.

If the upgrade fails or you cancel it, nothing after step 2 runs.

### `arch-maintenance clean`

1. Lists orphaned packages and asks before removing them.
2. Trims the pacman cache to the newest 2 versions of each installed package and drops uninstalled ones.
3. Cleans the AUR build cache with `yay -Sc`.
4. Shows journal size.

It also warns if makepkg's `debug` option is on, which builds a `*-debug` package for every AUR build.

## What runs automatically

| Task | When |
|---|---|
| Download pending updates into the cache, without installing them | daily |
| Update Flatpak apps and remove unused runtimes | daily |
| Status check, with a desktop notification if something needs attention | daily at 10:00 |
| Trim the package cache (upstream `paccache.timer`, keeps 2 versions) | weekly |
| Refresh the mirror list (upstream `reflector.timer`) | weekly |
| SSD TRIM (upstream `fstrim.timer`) | weekly |
| Snapshot the pacman database (newest 10 kept) | before every pacman transaction |
| Cap the journal at 1G | always |

The notification fires when the last full upgrade is more than 14 days old, or when there are `.pacnew` files, failed units, a pending reboot, or a filesystem above 90%.

Pre-downloading uses `checkupdates --download`, which syncs a temporary copy of the package databases. Your system's package database is never touched, so it can't leave you with a partial upgrade.

### Why upgrades aren't automated

An unattended `pacman -Syu --noconfirm` skips the steps that keep a rolling release healthy:

- **Arch news** sometimes announces upgrades that need manual steps before or after.
- **File conflicts** stop the transaction and need a decision about `--overwrite`.
- **`.pacnew` files** pile up when config defaults change, and stale configs cause subtle breakage.
- **DKMS modules** (NVIDIA, VirtualBox) rebuild on kernel upgrades. A failed build should be caught before rebooting.
- **AUR packages** are build scripts that run as you, and each update is worth a look.

### Flatpak

Flatpak apps bundle their own runtimes and don't depend on pacman packages, so they update safely unattended and removing orphans can't break them. The one link to the host is the GPU driver: after an NVIDIA driver upgrade, Flatpak needs the matching `org.freedesktop.Platform.GL.nvidia-*` extension, which `arch-maintenance update` installs right after the system upgrade.

## Configuration

### Installer options

| Option | Effect |
|---|---|
| `./install.sh --no-journald` | Skip the 1G journal cap |
| `./install.sh --uninstall` | Remove everything the installer added |

Uninstalling leaves the upstream `paccache`, `reflector` and `fstrim` timers enabled and keeps database snapshots.

Mirror selection is set in `/etc/xdg/reflector/reflector.conf` (country, protocol, sort order).

### Environment variables

| Variable | Default | Effect |
|---|---|---|
| `ARCH_MAINT_MAX_AGE_DAYS` | 14 | Days before a stale upgrade is flagged |
| `ARCH_MAINT_DISK_WARN_PCT` | 90 | Disk usage warning threshold |
| `ARCH_MAINT_CACHE_KEEP` | 2 | Package versions `clean` keeps in the cache |
| `DIFFPROG` | `vim -d` | Merge tool used by `pacdiff` |

## Reference

### Checking the timers

```bash
systemctl list-timers paccache.timer reflector.timer fstrim.timer pacman-predownload.timer flatpak-update.timer
systemctl --user list-timers arch-status.timer
journalctl -u pacman-predownload -u flatpak-update -u paccache
```

### Restoring the pacman database

```bash
ls /var/lib/pacman/backup/
sudo tar --zstd -xf /var/lib/pacman/backup/local-<stamp>.tar.zst -C /var/lib/pacman
```

### Installed files

| Path | Purpose |
|---|---|
| `/usr/local/bin/arch-maintenance` | The command |
| `/usr/local/lib/arch-maintenance/pacman-db-backup` | Database snapshot script |
| `/etc/pacman.d/hooks/00-arch-maintenance-db-backup.hook` | Runs the snapshot before each transaction |
| `/etc/systemd/system/pacman-predownload.{service,timer}` | Update pre-download |
| `/etc/systemd/system/flatpak-update.{service,timer}` | Flatpak updates (only if Flatpak is installed) |
| `/etc/systemd/system/paccache.service.d/arch-maintenance.conf` | Cache retention for the upstream `paccache.timer` |
| `/etc/systemd/user/arch-status.{service,timer}` | Daily status notification |
| `/etc/systemd/journald.conf.d/arch-maintenance.conf` | Journal size cap |

### Upgrading from v1

Run `./install.sh`. It removes the v1 `arch-maintenance.service`, `arch-maintenance.timer` and logrotate config if present. See [CHANGELOG.md](CHANGELOG.md) for what changed.

### Agent-assisted run

[PROMPT.md](PROMPT.md) has a prompt for a coding agent (e.g. Claude Code) that walks through installation and a full maintenance run, with you running the sudo and interactive steps.

## Testing

**CI** runs on every push in an `archlinux` container: shellcheck, `systemd-analyze verify` on all units, a real pacman transaction to check the snapshot hook and its rotation, and CLI smoke tests.

**Integration test** (`test/nspawn.sh`) boots a full systemd in a throwaway `systemd-nspawn` container built from an [Arch Linux Archive](https://archive.archlinux.org/) snapshot, so it starts out of date with real pending updates. Each run builds a fresh container under `/var/tmp` and deletes it on exit, including on failure or Ctrl-C.

```bash
sudo pacman -S --needed arch-install-scripts
sudo test/nspawn.sh run                    # install, hook, timers, services, status, uninstall
sudo test/nspawn.sh run --skip-download    # same, without pre-downloading updates
sudo test/nspawn.sh run --date 2026/06/01  # pick the archive snapshot (default: 90 days ago)
sudo test/nspawn.sh shell                  # log in to try `update` and `clean` by hand
```

Each run downloads about 500MB of bootstrap packages. The container shares the host kernel, so kernel upgrades, DKMS and the reboot check need a VM.

## License

[MIT](LICENSE)

## Credits

Originally based on [Fernando Cejas's Arch Linux system maintenance guide](https://fernandocejas.com/blog/engineering/2022-03-30-arch-linux-system-maintance/) and the [Arch Wiki system maintenance page](https://wiki.archlinux.org/title/System_maintenance).
