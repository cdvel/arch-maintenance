#!/usr/bin/env bash
# Offline test of the AUR drift check. ARCH_MAINT_AUR_FIXTURE stands in for
# pacman, the AUR RPC and cgit, so no network, AUR package or root is needed.
#
#   test/aur-drift.sh [path/to/arch-maintenance]

set -euo pipefail

BIN=${1:-$(cd "$(dirname "$0")/.." && pwd)/bin/arch-maintenance}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export ARCH_MAINT_AUR_FIXTURE=$WORK/fixture XDG_STATE_HOME=$WORK/state XDG_CACHE_HOME=$WORK/cache
FX=$ARCH_MAINT_AUR_FIXTURE
mkdir -p "$FX/PKGBUILD"

fail=0
# expect "description" "pattern" -- asserts the last output matches (or, with !, does not)
expect() {
  if [[ $2 == '!'* ]]; then
    if grep -qF -- "${2#!}" <<<"$OUT"; then echo "FAIL: $1 (unexpected: ${2#!})"; fail=1; else echo "ok:   $1"; fi
  elif grep -qF -- "$2" <<<"$OUT"; then echo "ok:   $1"; else echo "FAIL: $1 (missing: $2)"; fail=1; fi
}
run() { OUT=$("$BIN" "$@" 2>&1) && RC=0 || RC=$?; }

# rpc <name> <base> <version> <maintainer|null> <modified> [out_of_date]
rpc() {
  jq -n --arg n "$1" --arg b "$2" --arg v "$3" --argjson m "$([[ $4 == null ]] && echo null || echo "\"$4\"")" \
    --argjson t "$5" --argjson o "${6:-null}" \
    '{Name:$n, PackageBase:$b, Version:$v, Maintainer:$m, LastModified:$t, OutOfDate:$o}'
}
write_rpc() { jq -s '{type: "multiinfo", results: .}' >"$FX/rpc.json"; }

cat >"$FX/installed.tsv" <<TSV
alpha	alpha	1.0-1
beta	beta	2.0-1
gamma	gamma	3.0-1
delta	delta	1.0-1
epsilon	epsilon	1.0-1
zeta	zeta	1.0-1
eta	eta	1.0-1
mine	mine	1.0-1
theta	theta-debug	1.0-1
TSV
for b in alpha beta gamma delta epsilon zeta eta theta; do echo "pkgname=$b" >"$FX/PKGBUILD/$b"; done

baseline_rpc() {
  {
    rpc alpha alpha 1.0-1 alice 100
    rpc beta beta 2.0-1 null 100
    rpc gamma gamma 3.0-1 carol 100
    rpc delta delta 1.0-1 dave 100
    rpc epsilon epsilon 1.0-1 erin 100
    rpc zeta zeta 1.0-1 zoe 100
    rpc eta eta 1.0-1 eve 100
    rpc theta theta 1.0-1 tim 100
  } | write_rpc
}

echo "== no baseline"
baseline_rpc
run aur check
expect "orphan reported without a baseline" "beta: orphaned"
expect "tells how to record a baseline" "arch-maintenance aur baseline"

echo "== baseline"
run aur baseline --yes
expect "baseline written" "Wrote $XDG_STATE_HOME/arch-maintenance/aur-baseline.tsv"
OUT=$(<"$XDG_STATE_HOME/arch-maintenance/aur-baseline.tsv")
expect "locally built package recorded as not on the AUR" "$(printf 'mine\t1.0-1\t~')"
expect "split package keyed by its base" "$(printf 'theta\t1.0-1\ttim')"
run aur check
expect "clean state matches the baseline" "9 AUR packages match the baseline"
[[ $RC -eq 0 ]] && echo "ok:   exit 0 without drift" || { echo "FAIL: exit $RC without drift"; fail=1; }

echo "== drift"
{
  rpc alpha alpha 1.0-1 mallory 100
  rpc beta beta 2.0-1 null 100
  rpc delta delta 1.0-1 dave 200
  rpc epsilon epsilon 1.0-1 erin 200
  rpc zeta zeta 1.0-1 zoe 100 1700000000
  rpc theta theta 1.0-1 tim 100
  rpc eta eta 1.0-1 eve 100
  rpc mine mine 1.0-1 mallory 300
} | write_rpc
echo "changed" >"$FX/PKGBUILD/delta"
run aur check
[[ $RC -eq 1 ]] && echo "ok:   exit 1 on drift" || { echo "FAIL: exit $RC on drift"; fail=1; }
expect "maintainer change" "alpha: maintainer changed from alice to mallory"
expect "removal from the AUR" "gamma: no longer on the AUR (was maintained by carol)"
expect "silent PKGBUILD change" "delta: PKGBUILD changed without a version change"
expect "modified time alone is not drift" "!epsilon:"
expect "out of date is informational" "zeta: flagged out of date on the AUR"
expect "orphan unchanged since baseline is quiet" "!beta:"
expect "local package claimed on the AUR" "mine: now on the AUR (maintainer mallory) but was not at baseline"

echo "== orphan transitions"
run aur baseline --yes >/dev/null
{
  rpc alpha alpha 1.0-1 null 100
  rpc beta beta 2.0-1 mallory 100
} | write_rpc
run aur check
expect "orphaned" "alpha: orphaned (was maintained by mallory)"
expect "adopted" "beta: adopted by mallory (was orphaned)"

echo "== pending update does not trigger the PKGBUILD check"
baseline_rpc
run aur baseline --yes >/dev/null
{
  rpc alpha alpha 1.1-1 alice 500
  rpc beta beta 2.0-1 null 100
} | write_rpc
echo "new release" >"$FX/PKGBUILD/alpha"
run aur check
expect "new release is not flagged" "!alpha: PKGBUILD"

echo "== AUR unreachable"
rm "$FX/rpc.json"
run aur check
expect "skips with a message" "Drift check skipped: could not query the AUR"
[[ $RC -eq 0 ]] && echo "ok:   exit 0 when the AUR is unreachable" || { echo "FAIL: exit $RC"; fail=1; }

echo "== disabled"
OUT=$(ARCH_MAINT_AUR_CHECK=0 "$BIN" aur check 2>&1) && RC=0 || RC=$?
expect "no output when disabled" "!AUR packages"

echo "== arch-audit"
printf 'Package openssl is affected by CVE-2026-0001. High risk! Update to 3.5.2-1!\n' >"$FX/arch-audit.txt"
cat >"$FX/rpc.json" <<<'{"type":"multiinfo","results":[]}'
OUT=$("$BIN" status 2>&1) || true
expect "advisories listed" "Known vulnerabilities with a fix available in 1 installed package(s)"
rm "$FX/arch-audit.txt"
OUT=$("$BIN" status 2>&1) || true
expect "no advisories" "No installed package has a known vulnerability"

exit "$fail"
