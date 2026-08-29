#!/bin/sh
# Install Arch Terminal v1.2.0 and its pre-greeter system-information helper.

set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
theme_dir=/usr/share/sddm/themes/arch-terminal
helper_dir=/usr/lib/sddm
dropin_dir=/etc/systemd/system/sddm.service.d

if [ "$(id -u)" -ne 0 ]; then
    printf '%s\n' 'Run this installer with sudo or as root.' >&2
    exit 1
fi

install -d -m 0755 "$theme_dir" "$helper_dir" "$dropin_dir"
install -m 0644 "$project_dir/Main.qml" "$project_dir/metadata.desktop" \
    "$project_dir/theme.conf" "$project_dir/README.md" "$project_dir/LICENSE" "$theme_dir/"
install -d -m 0755 "$theme_dir/assets"
cp -a "$project_dir/assets/." "$theme_dir/assets/"
chown -R root:root "$theme_dir"
install -m 0755 "$project_dir/helpers/arch-terminal-system-info" \
    "$helper_dir/arch-terminal-system-info"
install -m 0644 "$project_dir/systemd/sddm.service.d/arch-terminal-system-info.conf" \
    "$dropin_dir/arch-terminal-system-info.conf"

systemctl daemon-reload
"$helper_dir/arch-terminal-system-info"

printf '%s\n' 'Arch Terminal v1.2.0 installed.'
printf '%s\n' 'Select Current=arch-terminal in /etc/sddm.conf.d/ and restart SDDM or reboot.'
