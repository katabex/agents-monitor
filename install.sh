#!/usr/bin/env bash
# Install Agents Monitor: copy into ~/.config/omarchy/plugins and replace the
# stock omarchy.agents widget on the bar.
#
#   ./install.sh    # copy + validate + opencode timer + shell restart
#                   # (re-run any time to deploy repo changes)
#
# Symlinks are rejected by omarchy-plugin-validate, so the install is a copy;
# the repo in ~/Repos/ktbx/agents-monitor stays the source of truth.
#
# The copy ends with `omarchy restart shell`: the "Local plugin changed,
# reloading" hot-reload path re-instantiates a CACHED QML component (verified
# 2026-09-06 with a line-shift canary — the engine kept serving the old
# Panel.qml), so changed QML only takes effect after a shell restart.
#
# The machine-local omarchy-pi-usage.timer stays enabled on purpose
# (option 2): the plugin refreshes all providers itself, and the timer
# keeps pi.json fresh between panel refreshes and when the shell is not
# running. The opencode sibling below ships from this repo for the same
# job on opencode.json.

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

# OpenCode usage: 5-minute local scan between panel refreshes and while
# the shell is down (same cadence as the pi timer).
mkdir -p "$HOME/.config/systemd/user"
cp "$SRC/systemd/omarchy-opencode-usage.service" \
   "$SRC/systemd/omarchy-opencode-usage.timer" \
   "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
systemctl --user enable --now omarchy-opencode-usage.timer

# QML changes need a shell restart: the hot-reload path serves cached
# components (see header comment).
omarchy restart shell

echo "==> Installed and shell restarted."
