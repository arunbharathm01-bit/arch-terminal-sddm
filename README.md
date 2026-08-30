# Arch Terminal v1.2.0

Arch Terminal is a production-ready terminal-style SDDM theme for Arch Linux,
Plasma 6, Qt 6, and SDDM 0.21+. It begins with a fictional, character-by-
character Linux boot sequence and fades into a transparent terminal login
prompt over a darkened custom wallpaper.

## Compatibility and dependencies

- Arch Linux, Plasma 6, Qt 6, and SDDM 0.21 or newer.
- Imports only standard Qt 6 modules: `QtQuick`, `QtQuick.Controls`, and
  `QtQuick.Layouts`; the generated runtime data object uses `QtQml`.
- Uses no shaders, `QtGraphicalEffects`, `MultiEffect`, layer rendering, or
  GPU-only effects. Wallpaper contrast uses a plain opacity overlay; terminal
  motion uses basic Qt Quick opacity and position animations.
- JetBrains Mono Regular is included in `assets/fonts/` with its OFL license;
  no external package or runtime dependency is required.

## Contents

```
arch-terminal/
├── Main.qml                         
├── metadata.desktop                 
├── theme.conf                       
├── install.sh                       
├── README.md                        
├── helpers/
│   └── arch-terminal-system-info     
├── systemd/sddm.service.d/
│   └── arch-terminal-system-info.conf 
└── assets/
    ├── wallpaper.svg                
    ├── arch-terminal.svg           
    └── fonts/
        ├── JetBrainsMono-Regular.ttf
        └── OFL.txt
```

## Installation

Use the installer rather than copying the theme directory by itself. Version
1.2.0 includes a small systemd pre-greeter helper that supplies the actual
distribution and running kernel information to QML.

```bash
cd /path/to/arch-terminal
sudo ./install.sh
```

The installer copies the theme to `/usr/share/sddm/themes/arch-terminal`,
installs the helper at `/usr/lib/sddm/arch-terminal-system-info`, adds an SDDM
systemd drop-in, and generates the first runtime data file. It does not restart
SDDM or change your selected theme.

Select the theme by creating `/etc/sddm.conf.d/10-arch-terminal.conf`:

```ini
[Theme]
Current=arch-terminal
```

Restart SDDM or reboot after selecting the theme. If SDDM fails to start,
switch to a TTY with `Ctrl` + `Alt` + `F3`, change `Current` to a known-good
theme, and restart SDDM.

## Preview safely

Run the greeter from an existing graphical session before activating it:

```bash
sudo ./helpers/arch-terminal-system-info
sddm-greeter --test-mode --theme "$(pwd)/arch-terminal"
```

Test mode deliberately makes authentication and system power actions inert.

## Custom wallpaper and configuration

`assets/wallpaper.svg` is the built-in default. To use a custom wallpaper,
copy it into `assets/` and change `Background` in `theme.conf`, for example:

```ini
Background=assets/my-wallpaper.jpg
```

An absolute file URL is also supported, though a wallpaper stored inside the
theme is more reliable because the `sddm` user must be able to read it.

`theme.conf` exposes the requested controls:

| Setting | Purpose |
| --- | --- |
| `TextColor`, `CursorColor` | terminal text and block cursor colors |
| `TypingSpeed` | milliseconds between characters |
| `BootDelay` | pause after each completed boot line |
| `BackgroundOpacity` | black overlay opacity from `0.0` to `1.0` |
| `AnimationDuration` | boot-to-login transition duration in milliseconds |

It also provides `PanelColor`, `PanelBorderColor`, `DimTextColor`, and
`BootSettleDelay`. For upgrade-safe local changes, create
`theme.conf.user` alongside `theme.conf`; SDDM merges it at runtime.

## Runtime system information

Before every SDDM start, the bundled helper reads `PRETTY_NAME` from
`/etc/os-release` (falling back to `NAME`) and calls `/usr/bin/uname -r` for
the running kernel. It writes the resulting, safely quoted QML data object
atomically to `/run/sddm/arch-terminal/SystemInfo.qml`; the theme only loads
that local object. QML never executes a shell command and does not require
local-file XHR permissions.

This produces boot and login text such as:

```text
Arch Linux
Linux 7.1.10-arch1-1
Kernel ready.
```

## SDDM integration

The theme calls documented SDDM APIs only: `sddm.login()`, `sddm.powerOff()`,
`sddm.reboot()`, and `sddm.suspend()`. The session menu is bound directly to
`sessionModel`, and unavailable power actions are disabled using SDDM's
capability flags.
