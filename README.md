# Omarchy

Omarchy is a beautiful, fun & agentic Linux distribution by DHH.

Read more at [omarchy.org](https://omarchy.org).

## This fork

This fork tracks upstream Quattro and previews three independent continuity workflows:

| Workflow | Setup | Everyday actions |
| --- | --- | --- |
| Reopen supported desktop applications after login | Setup > Session Restore | System > Session |
| Keep preference history and share settings between computers | Setup > Preferences | System > Preferences |
| Encrypt and back up home folders, including recovery from another computer | Setup > Backup | System > Backups and the backup bar widget |

Session restore and backups are opt-in. Preference publishing and pulling are explicit; conflicts stop for review, and applying settings keeps a local recovery snapshot. Hardware-specific configuration stays local. These features are independent: sharing preferences does not require setting up cloud backup.

See [desktop sessions](manual/31-dotfiles.md#remembering-your-desktop), [preference sharing](manual/31-dotfiles.md#preference-history-and-sharing), and [backups](manual/52-backups.md) for their behavior and limits. These changes are not yet part of official Omarchy packages. To build an installable preview, use the standard [local-source ISO workflow](https://github.com/omacom/omarchy-iso#creating-the-iso) with this checkout and `omarchy-pkgs`, so both runtime commands and their default assets are installed together.

The backup implementation builds on [Antoine Chevalier's upstream PR #7814](https://github.com/omacom/omarchy/pull/7814), with additional recovery and setup fixes. Session restoration and preference sharing remain separate branches for upstream review. The previous experimental implementations are preserved under `archive/*-20260915`; the integrated branch replaces their combined `omarchy backup sync` interface with `omarchy dots`.

### Updating from the earlier experimental fork

- Rerun **Setup > Session Restore** to enable or disable the new opt-in service. Existing saved application identities remain readable.
- Run **Setup > Preferences**, then explicitly publish from the computer with the settings you want to share. The previous per-device `profiles/*` branches and `main` are not automatically imported or modified.
- Configure **Setup > Backup** with a new restic repository or storage prefix. The earlier rclone file copies are not deleted or converted. Keep them until you have verified recovery from the new encrypted backup. An existing rclone provider can be used through restic's `rclone:REMOTE:new-prefix` repository URL, with rclone still installed and configured.

## The Omarchy Manual

The manual lives in [`manual/`](manual/), which is its authoritative source. It's
mirrored to [learn.omacom.io](https://learn.omacom.io/2/the-omarchy-manual), where
its screenshots are also hosted.

- [Welcome to Omarchy!](manual/01-welcome-to-omarchy.md)

**The Basics**

- [Getting Started](manual/02-getting-started.md)
- [Coming From Mac or Windows](manual/03-coming-from-mac-or-windows.md)
- [Navigation](manual/04-navigation.md)
- [The top bar](manual/05-the-top-bar.md)
- [Themes](manual/06-themes.md)
- [Hotkeys](manual/07-hotkeys.md)
- [Unified Clipboard & History](manual/08-unified-clipboard-history.md)
- [Reminders](manual/09-reminders.md)
- [Notices](manual/10-notices.md)
- [Text Extraction & Dictation](manual/11-text-extraction-dictation.md)
- [Screenshots & Recording](manual/12-screenshots-recording.md)
- [Toggles, idle & screensaver](manual/13-toggles-idle-screensaver.md)
- [Omarchy CLI](manual/14-omarchy-cli.md)

**The Applications**

- [Terminal](manual/15-terminal.md)
- [Neovim](manual/16-neovim.md)
- [AI](manual/17-ai.md)
- [Development Tools](manual/18-development-tools.md)
- [Shell Tools](manual/19-shell-tools.md)
- [Shell Functions](manual/20-shell-functions.md)
- [TUIs](manual/21-tuis.md)
- [GUIs](manual/22-guis.md)
- [Browsers](manual/23-browsers.md)
- [Commercial apps/services](manual/24-commercial-apps-services.md)
- [Web Apps](manual/25-web-apps.md)
- [Gaming](manual/26-gaming.md)
- [Filling out PDFs](manual/27-filling-out-pdfs.md)
- [Windows VM](manual/28-windows-vm.md)
- [Other Packages](manual/29-other-packages.md)

**Configuration**

- [Updates](manual/30-updates.md)
- [Dotfiles](manual/31-dotfiles.md)
- [Shell plugins](manual/32-shell-plugins.md)
- [Monitors](manual/33-monitors.md)
- [Keyboard, Mouse, Trackpad](manual/34-keyboard-mouse-trackpad.md)
- [Networking](manual/35-networking.md)
- [System sleep](manual/36-system-sleep.md)
- [Hardware authentication](manual/37-hardware-authentication.md)
- [Fonts](manual/38-fonts.md)
- [Backgrounds](manual/39-backgrounds.md)
- [Prompt](manual/40-prompt.md)
- [Branding](manual/41-branding.md)
- [Common tweaks](manual/42-common-tweaks.md)
- [Making your own theme](manual/43-making-your-own-theme.md)

**The Rest**

- [Mac support](manual/44-mac-support.md)
- [Troubleshooting](manual/45-troubleshooting.md)
- [FAQ](manual/46-faq.md)
- [System snapshots](manual/47-system-snapshots.md)
- [Security](manual/48-security.md)
- [Omarchy on...](manual/49-omarchy-on.md)
- [Dual Boot Install](manual/50-dual-boot-install.md)
- [Unattended Installs](manual/51-unattended-installs.md)
- [Backups](manual/52-backups.md)

## License

Omarchy is released under the [MIT License](https://opensource.org/licenses/MIT).
