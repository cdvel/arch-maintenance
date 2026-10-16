# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [2.0.1] - 2026-10-16

### Changed

- README: shorter wording, noun-phrase section titles.
- CI runs on pushes to `main` and on pull requests only, so tag pushes no longer start duplicate runs.
- CI retries the package install up to 3 times when a mirror fails to serve a package.
- CI uses `actions/checkout@v5` (Node.js 24).

## [2.0.0] - 2026-10-16

A redesign. v1 ran everything, including package upgrades, from one root script on a timer. v2 automates only the work that can't break the system and turns upgrades into a guided interactive command.

### Added

- `arch-maintenance` command, run as your normal user, with three subcommands:
  - `status`: last upgrade age, pending repo and AUR updates, `.pacnew` files, pending reboot, failed units, disk usage, cache sizes.
  - `update`: Arch news since the last upgrade, `yay -Syu` (or `pacman -Syu`), Flatpak update, `pacdiff` merge, reboot check.
  - `clean`: orphan review, pacman cache trim, AUR build cache cleanup.
- Daily status check (user timer) that sends a desktop notification when something needs attention.
- Daily pre-download of pending updates with `checkupdates --download`, which never touches the system package database.
- Daily Flatpak update and unused runtime removal.
- Pacman hook that snapshots the local database before every transaction, keeping the newest 10.
- Drop-in for the upstream `paccache.timer` to keep 2 versions of installed packages and drop uninstalled ones.
- Journal size cap (1G) through a journald drop-in.
- `install.sh` with `--uninstall` and `--no-journald`. Removes v1 units if present.
- Warning when makepkg's `debug` option is producing `*-debug` packages.
- CI workflow (shellcheck, unit verification, hook test, CLI smoke tests).
- `test/nspawn.sh` integration test in a throwaway container built from an Arch Linux Archive snapshot.
- `PROMPT.md` for an agent-assisted maintenance run.
- `LICENSE` file (MIT, as the README already stated).

### Changed

- Package upgrades are interactive only. No more `--noconfirm` upgrades from a timer.
- Mirror refresh, cache trimming and TRIM use the upstream `reflector.timer`, `paccache.timer` and `fstrim.timer`.
- Logs go to the systemd journal instead of files under a maintenance directory.

### Removed

- `arch_maintenance.sh`, `setup_maintenance.sh` and the biweekly `arch-maintenance.service`/`.timer`.
- `--yes` and `--yolo` modes.
- Flatpak reinstall after orphan removal. Flatpak apps don't depend on pacman packages, so orphan removal can't break them.
- Country detection through ipinfo.io for reflector. Configure `/etc/xdg/reflector/reflector.conf` instead.
- Log files and the logrotate config.

### Fixed

These v1 problems prevented it from working as scheduled automation:

- `setup_maintenance.sh` had an unterminated quote and failed before running anything.
- `OnCalendar=biweekly` is not valid systemd syntax, so the timer refused to load.
- The timer's `Requires=arch-maintenance.service` would have started a full run as soon as the timer was enabled.
- Paths disagreed: setup used `/home/arch-maintenance`, the service `/home/Maintenance`, the README `~/arch-maintenance`.
- `StandardOutput=append:` used `%Y-%m-%d`, which systemd reads as unit specifiers, not a date.
- The script ran `yay` as root, which yay refuses.
- `yay -Sc` as root cleaned root's cache, not the user's.
- The script always exited 0, so systemd never saw a failure.
- Pacman database backups were never pruned.

## [1.0.1] - 2026-10-16

Maintenance release on the v1 line.

### Fixed

- `setup_maintenance.sh`: add the missing closing quote on `MAINT_DIR`, which made the script fail before running anything ([#2](https://github.com/cdvel/arch-maintenance/pull/2), thanks @vasilliourous).

## [1.0.0] - 2025-03-04

Initial release: a single root script with a biweekly systemd timer, based on Fernando Cejas's Arch Linux maintenance guide.

### Added

- `arch_maintenance.sh`, run with sudo, performing in order:
  - pacman database backup to `/var/lib/pacman/backup`
  - mirror refresh with reflector, using ipinfo.io to detect the country
  - full system upgrade with `yay -Syu --noconfirm` or `pacman -Syu --noconfirm`
  - Flatpak update and unused runtime removal
  - package cache cleaning with `paccache` and `yay -Sc`
  - orphan removal with `pacman -Rns`
  - failed service and journal error report
  - SSD TRIM
  - journal vacuum (2 weeks)
  - disk usage report
  - Flatpak reinstall after orphan removal
- Options to skip steps (`--no-update`, `--no-cache-clean`, `--no-orphans`, `--no-journal-clean`, `--no-backup`, `--no-flatpak`, `--no-flatpak-reinstall`), plus `--yes`, `--yolo` and `--dry-run`.
- `setup_maintenance.sh` to install the script, a biweekly systemd service and timer, and a logrotate config.

[2.0.1]: https://github.com/cdvel/arch-maintenance/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/cdvel/arch-maintenance/compare/v1.0.0...v2.0.0
[1.0.1]: https://github.com/cdvel/arch-maintenance/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/cdvel/arch-maintenance/releases/tag/v1.0.0
