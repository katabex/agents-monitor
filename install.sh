#!/usr/bin/env bash
# Install Agents Monitor: copy into ~/.config/omarchy/plugins and replace the
# stock omarchy.agents widget on the bar.
#
#   ./install.sh    # copy + validate + timer + shell restart (re-run any
#                   # time to deploy repo changes)
#
# Symlinks are rejected by omarchy-plugin-validate, so the install is a copy;
# the repo in ~/Repos/ktbx/agents-monitor stays the source of truth.
#
# The copy ends with `omarchy restart shell`: the "Local plugin changed,
# reloading" hot-reload path re-instantiates a CACHED QML component (verified
# 2026-09-06 with a line-shift canary — the engine kept serving the old
# Panel.qml), so changed QML only takes effect after a shell restart.
#
# The omarchy-pi-usage.timer stays enabled on purpose (option 2): the plugin
# refreshes all four providers itself, and the timer keeps pi.json fresh
# between panel refreshes and when the shell is not running.

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

# Live agents view: 5-minute full scans between panel refreshes and while
# the shell is down. (The 15-second quick probe is driven by the bar widget
# itself, so it needs no unit.)
mkdir -p "$HOME/.config/systemd/user"
cp "$SRC/systemd/omarchy-agents-monitor-live.service" \
   "$SRC/systemd/omarchy-agents-monitor-live.timer" \
   "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
systemctl --user enable --now omarchy-agents-monitor-live.timer

# QML changes need a shell restart: the hot-reload path serves cached
# components (see header comment).
omarchy restart shell

echo "==> Installed and shell restarted."
echo "    omarchy-pi-usage.timer left enabled by design."
echo "    The bar badge lights up within ~15 s while any agent is running."
