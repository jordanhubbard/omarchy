# Continuity preview verification

Verified on September 15, 2026 against upstream `2fbac0c8e88eca704af1650ce721a494bd11a3d0`.

## Contribution boundaries

- Session restore is independently opt-in, restores supported applications and numbered workspaces, and does not synchronize session state.
- Preference sharing implements explicit publication, pull, conflict resolution, and recoverable local history from the dots plan. Automatic history hooks and timers are deferred. Explicit conflict choices are a deliberate difference from the plan's remote-wins fallback.
- Backup builds on Antoine Chevalier's upstream PR #7814. Recovery/setup fixes are contributed to that branch rather than proposed as a competing upstream implementation.

## Verification

The integrated tree passed CLI tests and 246 of 248 shell test files on an x86_64 Arch host with the sibling package checkout, a UTF-8 locale, and Python bytecode generation disabled. The remaining `legacy-power-udev-rules-migration-test.sh` and `omarchy-kernel-migration-test.sh` failures also reproduce in unchanged upstream. All focused session, dots, power-action, backup, menu, and dynamic QML text-format checks pass.

A disposable Omarchy 4.0.4 KVM guest ran the candidate runtime through Omarchy's development-link workflow. Graphical acceptance verified:

- Session menu labels, a real desktop-entry launch, workspace placement, and duplicate prevention.
- Preference menu labels and a real two-machine conflict through the file/version pickers, followed by applying and checking the selected version.
- Backup menu labels, machine/snapshot/path selection, and staged recovery from a real encrypted repository without overwriting the current home.
- A complete first backup enabling the timer and populating the backup panel, whose recovery action opened the picker.

A separate lifecycle pass enabled the real session service, rebooted through `omarchy-system-reboot`, confirmed a changed boot ID, logged in, and verified exactly one restored fixture application on workspace 3. Restarting the service did not duplicate it. Disabling the service preserved the application and saved snapshot.

Screenshots were inspected. Live testing found and corrected truncated menu labels and captured picker output that hid the interactive preference chooser.

## Limits

Cloud providers were not tested with live credentials. Git tests used real local bare repositories; backup tests used real encrypted local restic repositories, including multiple host identities. The VM used the development-link workflow rather than a newly published package or rebuilt ISO. Default asset coverage was checked against the package definitions. The physical test host was not rebooted and its installed Omarchy was not switched to this fork.
