#!/usr/bin/env bash
# Integration test for arch-maintenance in a systemd-nspawn container.
#
# The container is bootstrapped from an Arch Linux Archive snapshot and then
# pointed at current mirrors, so it starts out of date like a neglected machine:
# real pending updates, real news, real .pacnew files after upgrading.
# `run` and `shell` boot it with a volatile overlay, so every session starts
# from the same out-of-date state and nothing is written back.
#
#   sudo test/nspawn.sh build [YYYY/MM/DD]     create the container (default: 90 days ago)
#   sudo test/nspawn.sh run [--skip-download]  boot, run automated checks, power off
#   sudo test/nspawn.sh shell                  boot and log in as 'tester' for manual update/clean
#   sudo test/nspawn.sh destroy                delete the container
#
# The container shares the host kernel, so kernel, DKMS and reboot behaviour
# are not covered.

# Single-quoted snippets below run inside the container and expand there.
# shellcheck disable=SC2016

set -euo pipefail

readonly MACHINE=arch-maintenance-test
readonly ROOT=/var/lib/machines/$MACHINE
REPO=$(cd "$(dirname "$0")/.." && pwd)
readonly REPO
readonly CURRENT_MIRROR='https://geo.mirror.pkgbuild.com/$repo/os/$arch'
readonly PACKAGES=(base sudo pacman-contrib fakeroot reflector flatpak libnotify)

say() { printf '\e[1;34m==>\e[0m %s\n' "$1"; }
die() { printf '\e[31merror:\e[0m %s\n' "$1" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run with sudo (pacstrap and systemd-nspawn need root)."

# ---------------------------------------------------------------------------
# Container lifecycle
# ---------------------------------------------------------------------------

cmd_build() {
  local date=${1:-$(date -d '90 days ago' +%Y/%m/%d)} tmp
  [[ -e $ROOT ]] && die "$ROOT already exists; run 'destroy' first."
  command -v pacstrap >/dev/null || die "pacstrap not found: sudo pacman -S arch-install-scripts"

  tmp=$(mktemp -d)
  # shellcheck disable=SC2064 # expand $tmp now
  trap "rm -rf '$tmp'" EXIT
  echo "Server = https://archive.archlinux.org/repos/$date/\$repo/os/\$arch" >"$tmp/mirrorlist"
  cat >"$tmp/pacman.conf" <<EOF
[options]
Architecture = auto
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional

[core]
Include = $tmp/mirrorlist

[extra]
Include = $tmp/mirrorlist
EOF

  say "Bootstrapping $ROOT from the $date archive snapshot"
  mkdir -p "$ROOT"
  pacstrap -C "$tmp/pacman.conf" -K "$ROOT" "${PACKAGES[@]}"

  say "Pointing the container at current mirrors"
  echo "Server = $CURRENT_MIRROR" >"$ROOT/etc/pacman.d/mirrorlist"
  echo "$MACHINE" >"$ROOT/etc/hostname"

  say "Creating user 'tester' (passwordless sudo, lingering user manager)"
  systemd-nspawn -q -D "$ROOT" useradd -m -G wheel tester
  echo 'tester ALL=(ALL:ALL) NOPASSWD: ALL' >"$ROOT/etc/sudoers.d/tester"
  chmod 440 "$ROOT/etc/sudoers.d/tester"
  mkdir -p "$ROOT/var/lib/systemd/linger"
  touch "$ROOT/var/lib/systemd/linger/tester"

  say "Built. Next: sudo $0 run"
}

boot() {
  [[ -d $ROOT ]] || die "No container at $ROOT; run 'build' first."
  machinectl show "$MACHINE" &>/dev/null && die "$MACHINE is already running."

  say "Booting $MACHINE (volatile overlay; changes are discarded at power-off)"
  systemd-run --quiet --collect --unit="$MACHINE" \
    systemd-nspawn -q -b -D "$ROOT" -M "$MACHINE" --volatile=overlay \
    --console=passive --resolv-conf=copy-host --bind-ro="$REPO:/repo"

  local state
  for _ in {1..90}; do
    state=$(systemctl -M "$MACHINE" is-system-running 2>/dev/null) || true
    if [[ $state == running || $state == degraded ]] &&
      systemctl -M "$MACHINE" is-active --quiet user@1000.service 2>/dev/null; then
      return 0
    fi
    sleep 1
  done
  die "Container did not finish booting (last state: ${state:-unknown}). See: journalctl -u $MACHINE"
}

poweroff() {
  machinectl poweroff "$MACHINE" 2>/dev/null || true
  for _ in {1..30}; do
    machinectl show "$MACHINE" &>/dev/null || return 0
    sleep 1
  done
  machinectl terminate "$MACHINE" 2>/dev/null || true
}

cmd_destroy() {
  machinectl show "$MACHINE" &>/dev/null && poweroff
  [[ -e $ROOT ]] || die "Nothing to destroy."
  machinectl remove "$MACHINE"
  say "Removed $ROOT"
}

cmd_shell() {
  boot
  trap poweroff EXIT
  cat <<'EOF'

Logged in as 'tester' (passwordless sudo). The repo is mounted read-only at /repo.
Suggested manual checks:
  /repo/install.sh
  arch-maintenance                 # status: pending updates, no upgrade in pacman.log
  arch-maintenance update          # no yay here, so this uses sudo pacman -Syu
  arch-maintenance clean
  /repo/install.sh --uninstall
Exit the shell to power off; nothing is kept.

EOF
  machinectl shell "tester@$MACHINE"
}

# ---------------------------------------------------------------------------
# Automated checks
# ---------------------------------------------------------------------------

as_root() { systemd-run -M "$MACHINE" --quiet --pipe --wait -- "$@"; }
as_user() { systemd-run -M "tester@$MACHINE" --user --quiet --pipe --wait -- "$@"; }

PASS=0 FAIL=0 LOG=

check() {
  local name=$1
  shift
  if "$@" >"$LOG" 2>&1 </dev/null; then
    printf '  \e[32mPASS\e[0m %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf '  \e[31mFAIL\e[0m %s\n' "$name"
    tail -n 20 "$LOG" | sed 's/^/       /'
    FAIL=$((FAIL + 1))
  fi
}

readonly INSTALLED_FILES=(
  /usr/local/bin/arch-maintenance
  /usr/local/lib/arch-maintenance/pacman-db-backup
  /etc/pacman.d/hooks/00-arch-maintenance-db-backup.hook
  /etc/systemd/system/pacman-predownload.service
  /etc/systemd/system/pacman-predownload.timer
  /etc/systemd/system/flatpak-update.service
  /etc/systemd/system/flatpak-update.timer
  /etc/systemd/system/paccache.service.d/arch-maintenance.conf
  /etc/systemd/user/arch-status.service
  /etc/systemd/user/arch-status.timer
  /etc/systemd/journald.conf.d/arch-maintenance.conf
)

cmd_run() {
  local download=true
  [[ ${1:-} == --skip-download ]] && download=false

  LOG=$(mktemp)
  boot
  trap 'poweroff; rm -f "$LOG"' EXIT

  say "Install"
  check "install.sh succeeds" as_user /repo/install.sh
  check "install.sh is idempotent" as_user /repo/install.sh
  check "all files installed" as_root sh -c 'for f in "$@"; do [ -e "$f" ] || { echo "missing: $f"; exit 1; }; done' _ "${INSTALLED_FILES[@]}"
  local t
  for t in paccache reflector fstrim pacman-predownload flatpak-update; do
    check "$t.timer enabled" as_root systemctl is-enabled --quiet "$t.timer"
  done
  check "arch-status.timer active (user)" as_user systemctl --user is-active --quiet arch-status.timer
  check "paccache.service uses the drop-in (-rk2, -ruk0)" as_root sh -c \
    'systemctl show -p ExecStart paccache.service | grep -q -- "-rk2" &&
     systemctl show -p ExecStart paccache.service | grep -q -- "-ruk0"'

  say "Pacman hook"
  check "transaction creates a DB snapshot containing the local DB" as_root sh -c '
    rm -f /var/lib/pacman/backup/local-*.tar.zst
    pacman -S --noconfirm pacman-contrib >/dev/null
    snap=$(ls /var/lib/pacman/backup/local-*.tar.zst)
    tar --zstd -tf "$snap" | grep -q "^local/pacman-contrib-"'

  say "Status command"
  check "status reports pending updates" as_user sh -c \
    'out=$(arch-maintenance status) && echo "$out" && echo "$out" | grep -qE "[1-9][0-9]* repo \+"'
  check "status detects .pacnew files" as_user sh -c '
    sudo cp /etc/pacman.conf /etc/pacman.conf.pacnew
    arch-maintenance status | grep -q "pacman.conf.pacnew"; rc=$?
    sudo rm -f /etc/pacman.conf.pacnew; exit $rc'
  check "status --notify exits 0 without a notification daemon" as_user sh -c '
    sudo cp /etc/pacman.conf /etc/pacman.conf.pacnew
    arch-maintenance status --notify; rc=$?
    sudo rm -f /etc/pacman.conf.pacnew; exit $rc'
  check "arch-status.service runs (user)" as_user systemctl --user start arch-status.service
  check "refuses to run as root" as_root sh -c '! arch-maintenance status'

  say "Timer services"
  check "flatpak-update.service runs" as_root systemctl start flatpak-update.service
  if $download; then
    check "pacman-predownload fills the cache without touching the system DB" as_root sh -c '
      before=$(cat /var/lib/pacman/sync/*.db | sha256sum; pacman -Q | sha256sum)
      n0=$(ls /var/cache/pacman/pkg | wc -l)
      systemctl start pacman-predownload.service
      after=$(cat /var/lib/pacman/sync/*.db | sha256sum; pacman -Q | sha256sum)
      n1=$(ls /var/cache/pacman/pkg | wc -l)
      echo "cache files: $n0 -> $n1"
      [ "$before" = "$after" ] && [ "$n1" -gt "$n0" ]'
  else
    say "Skipping pre-download (--skip-download)"
  fi
  check "paccache.service runs" as_root systemctl start paccache.service

  say "Uninstall"
  check "install.sh --uninstall succeeds" as_user /repo/install.sh --uninstall
  check "all installed files removed" as_root sh -c 'for f in "$@"; do [ ! -e "$f" ] || { echo "left behind: $f"; exit 1; }; done' _ "${INSTALLED_FILES[@]}"
  check "arch-status.timer gone (user)" as_user sh -c '! systemctl --user is-enabled arch-status.timer'
  check "flatpak-update.timer gone" as_root sh -c '! systemctl is-enabled flatpak-update.timer'

  echo
  if ((FAIL)); then
    printf '\e[31m%d passed, %d failed\e[0m\n' "$PASS" "$FAIL"
    exit 1
  fi
  printf '\e[32mAll %d checks passed\e[0m\n' "$PASS"
}

case ${1:-} in
  build) cmd_build "${2:-}" ;;
  run) cmd_run "${2:-}" ;;
  shell) cmd_shell ;;
  destroy) cmd_destroy ;;
  *) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
