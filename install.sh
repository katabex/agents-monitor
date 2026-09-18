#!/usr/bin/env bash
# Install Agents Monitor: copy into ~/.config/omarchy/plugins and replace the
# stock omarchy.agents widget on the bar.
#
#   ./install.sh    # copy + validate + zai timer + shell restart
#                   # (re-run any time to deploy repo changes)
#
# Symlinks are rejected by omarchy-plugin-validate, so the install is a copy;
# the repo in ~/Repos/ktbx/agents-monitor stays the source of truth.
#
# The copy ends with `omarchy restart shell`: the "Local plugin changed,
# reloading" hot-reload path re-instantiates a CACHED QML component (verified
# 2026-09-06 with a line-shift canary - the engine kept serving the old
# Panel.qml), so changed QML only takes effect after a shell restart.
#
# The machine-local omarchy-pi-usage.timer stays enabled on purpose
# (option 2): the plugin refreshes all providers itself, and the timer
# keeps pi.json fresh between panel refreshes and when the shell is not
# running. The zai sibling below ships from this repo for the same job on
# zai.json - load-bearing there since the panel's own --limits-only
# refreshes skip every bundled probe.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/.config/omarchy/plugins/ptr.agents-monitor"

rm -rf "$DEST"
mkdir -p "$DEST"
cp -a "$SRC/." "$DEST/"
rm -rf "$DEST/.git" "$DEST/bin/__pycache__"

echo "==> Plugin copied to $DEST"

omarchy plugin validate "$DEST"

# Replace the stock widget: off with the old, on with the new, same spot
# (right section, between omarchy.tailscale and omarchy.bluetooth).
omarchy plugin disable omarchy.agents
omarchy plugin enable ptr.agents-monitor --after omarchy.tailscale

# Upgrade cleanup ≤ v0.4.3: the quota timer shipped as
# omarchy-opencode-usage before the probe moved to its own zai collector.
systemctl --user disable --now omarchy-opencode-usage.timer 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/omarchy-opencode-usage.service" \
      "$HOME/.config/systemd/user/omarchy-opencode-usage.timer"

# Z.ai quota: 5-minute network probe between panel refreshes and while
# the shell is down (same cadence as the pi timer). The pi timer ships
# here too, overwriting the machine-local predecessor unit of the same
# name: that one ran a September-6 ~/.local/bin build without
# subscription attribution, and its rewrites dropped the field every 5
# minutes (see the unit file for the full story).
mkdir -p "$HOME/.config/systemd/user"
cp "$SRC/systemd/omarchy-zai-usage.service" \
   "$SRC/systemd/omarchy-zai-usage.timer" \
   "$SRC/systemd/omarchy-pi-usage.service" \
   "$SRC/systemd/omarchy-pi-usage.timer" \
   "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
systemctl --user enable --now omarchy-zai-usage.timer omarchy-pi-usage.timer

# QML changes need a shell restart: the hot-reload path serves cached
# components (see header comment).
omarchy restart shell

echo "==> Installed and shell restarted."
