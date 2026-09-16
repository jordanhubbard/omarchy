#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

# restic's local backend makes a full round trip cheap and hermetic. Without
# restic there is nothing to round-trip, and the rest of the suite still covers
# the state machine with a stub.
if ! command -v restic >/dev/null; then
  pass "restic is not installed; skipping the backup round trip"
  exit 0
fi

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

fake_bin="$test_tmp/bin"
fake_home="$test_tmp/home"
mkdir -p "$fake_bin" "$fake_home/Documents" "$fake_home/.cache"

secrets_dir="$fake_home/.local/share/omarchy/backup"
state_dir="$fake_home/.local/state/omarchy/backup"
status_file="$state_dir/status.json"

stub() {
  local name="$1"
  cat >"$fake_bin/$name"
  chmod +x "$fake_bin/$name"
}

stub omarchy-cmd-missing <<'STUB'
#!/bin/bash
exit 1
STUB

stub omarchy-battery-below <<'STUB'
#!/bin/bash
exit 1
STUB

stub omarchy-notification-send <<'STUB'
#!/bin/bash
exit 0
STUB

omarchy() {
  HOME="$fake_home" \
    XDG_STATE_HOME="$fake_home/.local/state" \
    OMARCHY_PATH="$ROOT" \
    PATH="$fake_bin:$ROOT/bin:$PATH" \
    bash "$ROOT/bin/omarchy-$1" "${@:2}"
}

printf 'the numbers that matter\n' >"$fake_home/Documents/taxes.txt"
printf 'a note\n' >"$fake_home/Documents/note.txt"
printf 'regenerable\n' >"$fake_home/.cache/junk"

mkdir -p "$secrets_dir"
printf 'RESTIC_REPOSITORY=%s\n' "$test_tmp/repo" >"$secrets_dir/env"
printf 'test-passphrase\n' >"$secrets_dir/passphrase"
chmod 600 "$secrets_dir"/*

RESTIC_REPOSITORY="$test_tmp/repo" RESTIC_PASSWORD="test-passphrase" restic init >/dev/null

omarchy backup-run >/dev/null 2>&1

[[ $(jq -r '.last_backup.result' "$status_file") == "complete" ]] ||
  fail "the first backup completes against a real repository" "$(cat "$status_file")"
(( $(jq -r '.repository.snapshot_count' "$status_file") == 1 )) || fail "the snapshot is recorded"
pass "a real backup lands in a real repository"

RESTIC_REPOSITORY="$test_tmp/repo" RESTIC_PASSWORD="test-passphrase" \
  restic ls latest >"$test_tmp/listing" 2>/dev/null
grep -q 'Documents/taxes.txt' "$test_tmp/listing" || fail "personal files are in the backup"
! grep -q '.cache/junk' "$test_tmp/listing" || fail "caches are excluded from the backup" "$(cat "$test_tmp/listing")"
pass "the backup holds the files worth keeping and none of the regenerable ones"

# The point of the whole feature: a file that is gone comes back, without
# touching anything else that is still there.
rm "$fake_home/Documents/taxes.txt"
omarchy backup-restore "$fake_home/Documents/taxes.txt" >"$test_tmp/restore-output"

restored=$(find "$fake_home/Restored" -name taxes.txt | head -n 1)
[[ -n $restored ]] || fail "the restore produces a file" "$(cat "$test_tmp/restore-output")"
[[ $(<"$restored") == "the numbers that matter" ]] || fail "the restored file has its contents back"
[[ ! -e $fake_home/Documents/taxes.txt ]] || fail "a default restore does not write over the live folder"
pass "a deleted file comes back into a staging folder"

printf 'edited badly\n' >"$fake_home/Documents/note.txt"
printf 'restore\n' | omarchy backup-restore "$fake_home/Documents/note.txt" --in-place >"$test_tmp/in-place-output"

[[ $(<"$fake_home/Documents/note.txt") == "a note" ]] || fail "an in-place restore puts the old version back"
grep -q 'edited badly' -r "$fake_home/Restored" ||
  fail "an in-place restore keeps the version it replaced" "$(cat "$test_tmp/in-place-output")"
pass "an in-place restore is itself recoverable"

printf 'no\n' | omarchy backup-restore "$fake_home/Documents/note.txt" --in-place >/dev/null 2>&1 || true
[[ $(<"$fake_home/Documents/note.txt") == "a note" ]] || fail "an unconfirmed in-place restore changes nothing"
pass "an in-place restore that is not confirmed does nothing"

set +e
omarchy backup-restore "$fake_home/Documents/note.txt" --at "1999-01-01" >/dev/null 2>"$test_tmp/at-error"
status=$?
set -e
(( status != 0 )) || fail "restoring from before the first backup fails"
grep -q 'no backup from before' "$test_tmp/at-error" || fail "the failure says why" "$(cat "$test_tmp/at-error")"
pass "asking for a version older than the oldest backup fails clearly"

real_restic=$(command -v restic)
repo_command() {
  RESTIC_REPOSITORY="$test_tmp/repo" RESTIC_PASSWORD='test-passphrase' "$real_restic" "$@"
}

# Completion is discoverable after losing the local state, and a later unmarked
# (partial/interrupted/legacy) snapshot cannot silently replace it.
printf 'not verified\n' >"$fake_home/Documents/note.txt"
repo_command backup --quiet --tag omarchy "$fake_home" >/dev/null
rm "$status_file"
omarchy backup-restore "$fake_home/Documents/note.txt" >"$test_tmp/reinstall-output"
recovered=$(sed -n 's/^Recovered files: //p' "$test_tmp/reinstall-output")
[[ $(<"$recovered") == 'a note' ]] || fail 'reinstall selects the last repository-marked complete snapshot'
pass 'completion markers survive reinstall and exclude newer unverified backups'

# A shared repository's newest snapshot may belong to a different machine.
printf 'second machine\n' >"$fake_home/Documents/note.txt"
other_id=$(repo_command backup --json --host second-machine --tag omarchy "$fake_home" | jq -r 'select(.message_type == "summary") | .snapshot_id')
repo_command tag --add omarchy-complete "$other_id" >/dev/null
omarchy backup-restore Documents/note.txt --host second-machine >"$test_tmp/other-output"
recovered=$(sed -n 's/^Recovered files: //p' "$test_tmp/other-output")
[[ $(<"$recovered") == 'second machine' ]] || fail 'host selection restores the chosen machine'
omarchy backup-restore Documents/note.txt >"$test_tmp/default-host-output"
recovered=$(sed -n 's/^Recovered files: //p' "$test_tmp/default-host-output")
[[ $(<"$recovered") == 'a note' ]] || fail 'default recovery stays on this machine'
pass 'shared-repository recovery keeps host selection explicit'

if omarchy backup-restore Documents/note.txt --host never-backed-up >/dev/null 2>&1; then
  fail 'missing host must not fall back to another machine'
fi
pass 'a missing host never falls back to an unrelated backup'

# If the download fails, in-place recovery must neither claim success nor
# move/overwrite the current file. Snapshot discovery still uses real restic.
export TEST_REAL_RESTIC="$real_restic"
stub restic <<'STUB'
#!/bin/bash
if [[ " $* " == *' restore '* ]]; then exit 42; fi
exec "$TEST_REAL_RESTIC" "$@"
STUB
printf 'precious live edit\n' >"$fake_home/Documents/note.txt"
if printf 'restore\n' | omarchy backup-restore Documents/note.txt --in-place >"$test_tmp/failed-output" 2>&1; then
  fail 'a failed download must return failure'
fi
[[ $(<"$fake_home/Documents/note.txt") == 'precious live edit' ]] || fail 'failed recovery leaves the live file intact'
! grep -q '^Restored ' "$test_tmp/failed-output" || fail 'a failed restore cannot announce success'
pass 'download failure leaves live files intact and reports failure'
