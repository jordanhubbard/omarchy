#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

fake_bin="$test_tmp/bin"
fake_home="$test_tmp/home"
mkdir -p "$fake_bin" "$fake_home"

secrets_dir="$fake_home/.local/share/omarchy/backup"
config_dir="$fake_home/.config/omarchy/backup"
unit_dir="$fake_home/.config/systemd/user"
recovery_card="$fake_home/Omarchy Backup Recovery.txt"

printf 'correct-horse-battery-staple\n' >"$test_tmp/passphrase"

stub() {
  local name="$1"
  cat >"$fake_bin/$name"
  chmod +x "$fake_bin/$name"
}

stub restic <<'STUB'
#!/bin/bash
printf 'restic %s\n' "$*" >>"$TEST_LOG"
if [[ $1 == "cat" ]]; then
  exit "${STUB_PROBE_EXIT:-10}"
fi
exit 0
STUB

for command in omarchy-pkg-add omarchy-plugin-enable omarchy-plugin-disable systemctl gum fusermount; do
  stub "$command" <<STUB
#!/bin/bash
printf '$command %s\n' "\$*" >>"\$TEST_LOG"
exit 0
STUB
done

setup() {
  TEST_LOG="$test_tmp/calls.log" \
    HOME="$fake_home" \
    XDG_STATE_HOME="$fake_home/.local/state" \
    OMARCHY_PATH="$ROOT" \
    PATH="$fake_bin:$ROOT/bin:$PATH" \
    bash "$ROOT/bin/omarchy-setup-backup" "$@"
}

mode() {
  stat -c '%a' "$1"
}

: >"$test_tmp/calls.log"
setup --repository "$test_tmp/repo" --passphrase-file "$test_tmp/passphrase" --no-first-backup >/dev/null

# The repository is created only after the probe says there is nothing there.
grep -q '^restic cat config' "$test_tmp/calls.log" || fail "the destination is probed before anything is created"
grep -q '^restic init' "$test_tmp/calls.log" || fail "an absent repository is initialized"
pass "setup probes the destination and initializes only what is missing"

[[ $(mode "$secrets_dir") == "700" ]] || fail "the secrets directory is private" "$(mode "$secrets_dir")"
[[ $(mode "$secrets_dir/env") == "600" ]] || fail "the credentials file is private"
[[ $(mode "$secrets_dir/passphrase") == "600" ]] || fail "the passphrase file is private"
grep -q "RESTIC_REPOSITORY=$test_tmp/repo" "$secrets_dir/env" || fail "the repository is recorded"
! grep -q "correct-horse-battery-staple" "$secrets_dir/env" || fail "the passphrase does not leak into the environment file"
pass "credentials and passphrase are written privately, and separately"

# ~/.config is versioned and synced by people; a delete-capable credential must
# not ride along with it.
! grep -rq "correct-horse-battery-staple" "$config_dir" || fail "the passphrase is not in ~/.config"
! grep -rq "RESTIC_REPOSITORY" "$config_dir" 2>/dev/null || fail "credentials are not in ~/.config"
grep -q "BACKUP_MAINTENANCE_HOST=$(hostname)" "$config_dir/settings" ||
  fail "the machine that set the repository up owns maintenance" "$(cat "$config_dir/settings")"
pass "only non-secret settings land in ~/.config"

[[ -f $recovery_card ]] || fail "a recovery card is written"
[[ $(mode "$recovery_card") == "600" ]] || fail "the recovery card is private"
grep -q "$test_tmp/repo" "$recovery_card" || fail "the recovery card names the repository"
! grep -q "correct-horse-battery-staple" "$recovery_card" ||
  fail "the recovery card carries no live secret; the passphrase is written on by hand"
pass "the recovery card explains the restore without holding the keys"

[[ -L $unit_dir/omarchy-backup.timer ]] || fail "the timer is linked into the user's units"
[[ -L $unit_dir/omarchy-backup.service ]] || fail "the service is linked into the user's units"
! grep -q 'systemctl --user enable --now omarchy-backup.timer' "$test_tmp/calls.log" || fail "unverified backups must not enable a timer"
! grep -q 'omarchy-plugin-enable omarchy.backup' "$test_tmp/calls.log" || fail "unverified backups must not show a healthy widget"
pass "unverified setup leaves scheduling disabled"

# Re-running the wizard must not double up or fail on what already exists.
: >"$test_tmp/calls.log"
setup --repository "$test_tmp/repo" --passphrase-file "$test_tmp/passphrase" --no-first-backup >/dev/null
[[ $(ls "$unit_dir" | wc -l) == "2" ]] || fail "re-running the setup does not duplicate units"
pass "the setup is idempotent"

# A passphrase that does not open an existing repository is a stop, not a
# reason to create a second repository next to the first.
: >"$test_tmp/calls.log"
set +e
STUB_PROBE_EXIT=12 setup --repository "$test_tmp/repo" --passphrase-file "$test_tmp/passphrase" --no-first-backup >/dev/null 2>"$test_tmp/stderr"
status=$?
set -e
(( status != 0 )) || fail "a wrong passphrase fails the setup"
grep -qi 'passphrase does not open' "$test_tmp/stderr" || fail "the wrong passphrase is named" "$(cat "$test_tmp/stderr")"
! grep -q '^restic init' "$test_tmp/calls.log" || fail "a wrong passphrase must not initialize anything"
pass "a wrong passphrase stops the setup without creating a repository"

: >"$test_tmp/calls.log"
set +e
STUB_PROBE_EXIT=1 setup --repository "$test_tmp/repo" --passphrase-file "$test_tmp/passphrase" --no-first-backup >/dev/null 2>"$test_tmp/stderr"
status=$?
set -e
(( status != 0 )) || fail "an unreachable destination fails the setup"
! grep -q '^restic init' "$test_tmp/calls.log" || fail "an unreachable destination must not initialize anything"
pass "an unreachable destination stops the setup without creating a repository"

: >"$test_tmp/calls.log"
setup --remove >"$test_tmp/removal"

grep -q 'systemctl --user disable omarchy-backup.timer' "$test_tmp/calls.log" || fail "removal disables the schedule"
grep -q 'omarchy-plugin-disable omarchy.backup' "$test_tmp/calls.log" || fail "removal takes the widget out of the bar"
[[ ! -e $secrets_dir ]] || fail "removal deletes the local credentials"
[[ ! -e $unit_dir/omarchy-backup.timer ]] || fail "removal unlinks the units"
grep -qi 'untouched' "$test_tmp/removal" || fail "removal says the backups themselves are still there" "$(cat "$test_tmp/removal")"
pass "removal forgets the destination without pretending to delete the backups"

# Values saved for later sourcing must remain literal, including shell syntax.
literal_secret='a secret with spaces $(false) `false` "quotes"'
printf '%s' "$literal_secret" >"$test_tmp/access-key"
setup --repository "$test_tmp/repo with spaces" --secret-access-key-file "$test_tmp/access-key" --passphrase-file "$test_tmp/passphrase" --no-first-backup >/dev/null
saved_secret=$(source "$secrets_dir/env"; printf '%s' "$AWS_SECRET_ACCESS_KEY")
[[ $saved_secret == "$literal_secret" ]] || fail 'credential characters must round-trip literally'
saved_repository=$(source "$secrets_dir/env"; printf '%s' "$RESTIC_REPOSITORY")
[[ $saved_repository == "$test_tmp/repo with spaces" ]] || fail 'repository paths with spaces must round-trip'
pass 'credential and repository values are quoted for literal reload'

cp "$secrets_dir/env" "$test_tmp/previous-env"
cp "$secrets_dir/passphrase" "$test_tmp/previous-passphrase"
printf 'incorrect candidate\n' >"$test_tmp/bad-passphrase"
if STUB_PROBE_EXIT=12 setup --repository "$test_tmp/different-repo" --passphrase-file "$test_tmp/bad-passphrase" --no-first-backup >/dev/null 2>&1; then
  fail 'incorrect candidate credentials must fail'
fi
cmp "$secrets_dir/env" "$test_tmp/previous-env" || fail 'failed setup preserves working credentials'
cmp "$secrets_dir/passphrase" "$test_tmp/previous-passphrase" || fail 'failed setup preserves working passphrase'
pass 'failed reconfiguration preserves the working backup credentials'

stub systemctl <<'STUB'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$TEST_LOG"
if [[ $* == '--user start omarchy-backup.service' ]]; then
  mkdir -p "$HOME/.local/state/omarchy/backup"
  printf '{"run_id":"%s","last_backup":{"result":"%s","unreadable":["test-file"]}}' "$RANDOM" "${STUB_FIRST_RESULT:-partial}" >"$HOME/.local/state/omarchy/backup/status.json"
fi
STUB
: >"$test_tmp/calls.log"
if setup --repository "$test_tmp/repo" --passphrase-file "$test_tmp/passphrase" >/dev/null 2>&1; then
  fail 'an incomplete first backup must not complete setup'
fi
! grep -q 'enable --now omarchy-backup.timer' "$test_tmp/calls.log" || fail 'an incomplete first backup cannot enable scheduling'
pass 'an incomplete first backup leaves scheduling off'

: >"$test_tmp/calls.log"
STUB_FIRST_RESULT=complete setup --repository "$test_tmp/repo" --passphrase-file "$test_tmp/passphrase" >/dev/null
grep -q 'enable --now omarchy-backup.timer' "$test_tmp/calls.log" || fail 'a complete verified backup enables scheduling'
pass 'a complete first run enables the backup schedule'

: >"$test_tmp/calls.log"
if setup --repository >/dev/null 2>&1; then fail 'missing repository value must fail before prompting'; fi
[[ ! -s $test_tmp/calls.log ]] || fail 'invalid arguments must not configure anything'
pass 'missing setup arguments fail before changing backup configuration'

# Exercise the TTY-only recovery offer with a real repository, including a
# reinstall that retains its hostname. Gum/systemd remain isolated stubs.
if command -v restic >/dev/null && command -v script >/dev/null; then
  export REAL_RESTIC
  REAL_RESTIC=$(command -v restic)
  export RESTIC_REPOSITORY="$test_tmp/existing-repo" RESTIC_PASSWORD_FILE="$test_tmp/passphrase"
  export TEST_RECOVERY_HOST
  TEST_RECOVERY_HOST=$(hostname)
  mkdir -p "$test_tmp/old-home"
  printf 'old machine file\n' > "$test_tmp/old-home/recovered-note"
  "$REAL_RESTIC" init >/dev/null
  "$REAL_RESTIC" backup --host "$TEST_RECOVERY_HOST" --tag omarchy,omarchy-complete "$test_tmp/old-home" >/dev/null
  stub restic <<'STUB'
#!/bin/bash
exec "$REAL_RESTIC" "$@"
STUB
  stub gum <<'STUB'
#!/bin/bash
if [[ $1 == choose ]]; then printf '%s\n' "$TEST_RECOVERY_HOST"; fi
exit 0
STUB
  printf -v setup_command '%q ' env "TEST_LOG=$test_tmp/calls.log" "HOME=$fake_home" \
    "XDG_STATE_HOME=$fake_home/.local/state" "OMARCHY_PATH=$ROOT" "PATH=$fake_bin:$ROOT/bin:$PATH" \
    bash "$ROOT/bin/omarchy-setup-backup" --repository "$RESTIC_REPOSITORY" \
    --passphrase-file "$test_tmp/passphrase" --no-first-backup
  script -q -e -c "$setup_command" /dev/null </dev/null > "$test_tmp/recovery-output"
  recovered=$(find "$fake_home/Restored" -name recovered-note -print -quit)
  [[ -n $recovered && $(cat "$recovered") == 'old machine file' ]] || fail 'setup offers existing same-host snapshots and stages their files'
  [[ ! -e $fake_home/recovered-note ]] || fail 'setup recovery preserves the current home'
  pass 'interactive setup finds existing same-host backups and recovers into staging'
else
  pass 'restic or script unavailable; skipping real interactive setup recovery'
fi
