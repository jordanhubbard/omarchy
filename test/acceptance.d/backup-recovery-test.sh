#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

fixture=$(mktemp -d)
terminal_address=""
cleanup() {
  omarchy-menu close >/dev/null 2>&1 || true
  if [[ -n $terminal_address ]]; then
    hyprctl dispatch "hl.dsp.window.close({ window = \"address:$terminal_address\" })" >/dev/null 2>&1 || true
  fi
  rm -rf "$fixture"
}
trap cleanup EXIT

omarchy-menu summon system.backup
wait_until 'backups menu exposes recovery' 15 screen_contains 'Browse Backups'
screenshot success-backups-menu
omarchy-menu close

omarchy-cmd-present restic || fail 'install the optional restic package in this disposable VM before recovery acceptance'
home="$fixture/home"
mkdir -p "$home/Documents" "$home/.local/share/omarchy/backup"
printf 'recovery fixture\n' > "$home/Documents/note.txt"
printf 'RESTIC_REPOSITORY=%q\n' "$fixture/repo" > "$home/.local/share/omarchy/backup/env"
printf 'acceptance-fixture-passphrase\n' > "$home/.local/share/omarchy/backup/passphrase"
export RESTIC_REPOSITORY="$fixture/repo" RESTIC_PASSWORD_FILE="$home/.local/share/omarchy/backup/passphrase"
restic init >/dev/null
snapshot=$(restic backup --json --host recovery-fixture --tag omarchy "$home" | jq -r 'select(.message_type == "summary") | .snapshot_id')
restic tag --add omarchy-complete "$snapshot" >/dev/null
rm "$home/Documents/note.txt"

before=$(hyprctl -j clients | jq -r '.[].address')
printf -v command '%q ' env "HOME=$home" "XDG_STATE_HOME=$home/.local/state" omarchy-backup-restore
omarchy-launch-floating-terminal-with-presentation "$command" &
new_terminal() {
  terminal_address=$(hyprctl -j clients | jq -r --arg before "$before" '.[] | select(.address as $a | $before | split("\n") | index($a) | not) | .address' | head -1)
  [[ -n $terminal_address ]]
}
wait_until 'presentation terminal opens' 20 new_terminal
wait_until 'recovery computer picker is visible' 20 screen_contains 'Recover from which computer'
screenshot success-backups-select-computer
wtype -k Return
wait_until 'complete snapshot picker is visible' 15 screen_contains 'Choose a complete backup'
screenshot success-backups-select-snapshot
wtype -k Return
wait_until 'recovery path input is visible' 15 screen_contains 'Path inside'
wtype -M ctrl -k a -k k -m ctrl 'Documents/note.txt'
screenshot success-backups-entered-path
wtype -k Return
wait_until 'recovery reports its staged files' 30 screen_contains 'Recovered files'
screenshot success-backups-recovered-file
recovered=$(find "$home/Restored" -name note.txt -print -quit)
[[ -n $recovered && $(cat "$recovered") == 'recovery fixture' ]] || fail 'menu recovery returns the selected file'
[[ ! -e $home/Documents/note.txt ]] || fail 'menu recovery does not overwrite the live home'
pass 'recovery picker selects a host, snapshot, and file using a real encrypted repository'
