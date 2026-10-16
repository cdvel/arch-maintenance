#!/usr/bin/env bash
# Install or remove arch-maintenance.
# Run as your normal user from the repo directory; sudo is used for system files.
#
#   ./install.sh                 install and enable everything
#   ./install.sh --no-journald   skip the journal size cap
#   ./install.sh --uninstall     remove everything this script installed

set -euo pipefail
cd "$(dirname "$0")"

readonly BIN=/usr/local/bin/arch-maintenance
readonly LIBEXEC=/usr/local/lib/arch-maintenance
readonly HOOK=/etc/pacman.d/hooks/00-arch-maintenance-db-backup.hook
readonly SYSTEMD=/etc/systemd/system
readonly USER_SYSTEMD=/etc/systemd/user
readonly JOURNALD=/etc/systemd/journald.conf.d/arch-maintenance.conf

say() { printf '\e[1;34m==>\e[0m %s\n' "$1"; }
die() { printf '\e[31merror:\e[0m %s\n' "$1" >&2; exit 1; }
have() { command -v "$1" &>/dev/null; }

[[ $EUID -ne 0 ]] || die "Run as your normal user (the user timer is enabled for whoever runs this)."

# Remove the v1 layout (biweekly root timer + log files), if any piece of it exists.
remove_legacy() {
  local f
  for f in $SYSTEMD/arch-maintenance.service $SYSTEMD/arch-maintenance.timer /etc/logrotate.d/arch-maintenance; do
    if [[ -e $f ]]; then
      say "Removing legacy $f"
      sudo systemctl disable --now arch-maintenance.timer 2>/dev/null || true
      sudo rm -f "$f"
    fi
  done
}

install_all() {
  local journald=true
  [[ ${1:-} == --no-journald ]] && journald=false

  local missing=()
  have paccache || missing+=(pacman-contrib)
  have fakeroot || missing+=(fakeroot) # optional dep of pacman-contrib, required by checkupdates
  have reflector || missing+=(reflector)
  have notify-send || missing+=(libnotify)
  if (( ${#missing[@]} )); then
    die "Missing packages. Install them first: sudo pacman -S --needed ${missing[*]}"
  fi
  have yay || say "yay not found: AUR updates and news checks will be skipped"

  remove_legacy

  say "Installing command and pacman hook"
  sudo install -Dm755 bin/arch-maintenance "$BIN"
  sudo install -Dm755 libexec/pacman-db-backup "$LIBEXEC/pacman-db-backup"
  sudo install -Dm644 hooks/00-arch-maintenance-db-backup.hook "$HOOK"

  say "Installing systemd units"
  sudo install -Dm644 systemd/system/paccache.service.d/arch-maintenance.conf \
    "$SYSTEMD/paccache.service.d/arch-maintenance.conf"
  sudo install -Dm644 systemd/system/pacman-predownload.service "$SYSTEMD/pacman-predownload.service"
  sudo install -Dm644 systemd/system/pacman-predownload.timer "$SYSTEMD/pacman-predownload.timer"
  sudo install -Dm644 systemd/user/arch-status.service "$USER_SYSTEMD/arch-status.service"
  sudo install -Dm644 systemd/user/arch-status.timer "$USER_SYSTEMD/arch-status.timer"
  if have flatpak; then
    sudo install -Dm644 systemd/system/flatpak-update.service "$SYSTEMD/flatpak-update.service"
    sudo install -Dm644 systemd/system/flatpak-update.timer "$SYSTEMD/flatpak-update.timer"
  fi
  if $journald; then
    say "Capping journal size (SystemMaxUse=1G)"
    sudo install -Dm644 journald/arch-maintenance.conf "$JOURNALD"
    sudo systemctl restart systemd-journald
  fi

  say "Enabling timers"
  sudo systemctl daemon-reload
  sudo systemctl enable --now paccache.timer reflector.timer fstrim.timer pacman-predownload.timer
  have flatpak && sudo systemctl enable --now flatpak-update.timer
  systemctl --user daemon-reload
  systemctl --user enable --now arch-status.timer

  say "Done. Next runs:"
  systemctl list-timers --no-pager paccache.timer reflector.timer fstrim.timer \
    pacman-predownload.timer flatpak-update.timer 2>/dev/null || true
  systemctl --user list-timers --no-pager arch-status.timer || true
  echo
  echo "Run 'arch-maintenance' for a status report, 'arch-maintenance update' to upgrade."
}

uninstall_all() {
  say "Disabling timers added by arch-maintenance"
  systemctl --user disable --now arch-status.timer 2>/dev/null || true
  sudo systemctl disable --now flatpak-update.timer pacman-predownload.timer 2>/dev/null || true

  say "Removing files"
  sudo rm -f "$BIN" "$HOOK" "$JOURNALD" \
    "$SYSTEMD/flatpak-update.service" "$SYSTEMD/flatpak-update.timer" \
    "$SYSTEMD/pacman-predownload.service" "$SYSTEMD/pacman-predownload.timer" \
    "$SYSTEMD/paccache.service.d/arch-maintenance.conf" \
    "$USER_SYSTEMD/arch-status.service" "$USER_SYSTEMD/arch-status.timer"
  sudo rm -rf "$LIBEXEC"
  sudo rmdir --ignore-fail-on-non-empty "$SYSTEMD/paccache.service.d" 2>/dev/null || true
  remove_legacy

  sudo systemctl daemon-reload
  systemctl --user daemon-reload
  [[ -e $JOURNALD ]] || sudo systemctl restart systemd-journald

  say "Done. paccache.timer, reflector.timer and fstrim.timer are upstream units and were left enabled."
  say "Snapshots in /var/lib/pacman/backup were kept."
}

case ${1:-} in
  --uninstall) uninstall_all ;;
  '' | --no-journald) install_all "${1:-}" ;;
  -h | --help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "Unknown option: $1 (see --help)" ;;
esac
