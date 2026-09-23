#!/usr/bin/env bash
# Uninstall Agents Monitor: remove it from the bar and restore the stock
# omarchy.agents widget. The omarchy-pi-usage.timer stays enabled (option 2),
# so the pi tab keeps refreshing even under the stock widget.

set -euo pipefail

DEST="$HOME/.config/omarchy/plugins/katabex.agents-monitor"
OLD_DEST="$HOME/.config/omarchy/plugins/ptr.agents-monitor"

omarchy plugin disable katabex.agents-monitor 2>/dev/null || true
omarchy plugin disable ptr.agents-monitor 2>/dev/null || true
omarchy plugin enable omarchy.agents --after omarchy.tailscale

# Z.ai and pi usage timers: off with the plugin (their collectors live
# in it). The pi unit replaced a machine-local predecessor of the same
# name (see install.sh), so removing it also removes that one.
systemctl --user disable --now omarchy-zai-usage.timer omarchy-pi-usage.timer 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/omarchy-zai-usage.service" \
      "$HOME/.config/systemd/user/omarchy-zai-usage.timer" \
      "$HOME/.config/systemd/user/omarchy-pi-usage.service" \
      "$HOME/.config/systemd/user/omarchy-pi-usage.timer"

# Legacy cleanup for installs ≤ v0.4.3: the timer shipped as
# omarchy-opencode-usage before the z.ai quota probe moved to its own
# collector and record (v0.5.0).
systemctl --user disable --now omarchy-opencode-usage.timer 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/omarchy-opencode-usage.service" \
      "$HOME/.config/systemd/user/omarchy-opencode-usage.timer"

# Legacy cleanup for installs ≤ v0.1.0: the live-agents timer no longer
# ships with the plugin.
systemctl --user disable --now omarchy-agents-monitor-live.timer 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/omarchy-agents-monitor-live.service" \
      "$HOME/.config/systemd/user/omarchy-agents-monitor-live.timer"
systemctl --user daemon-reload

if [[ -L $DEST ]]; then
  rm "$DEST"
elif [[ -d $DEST ]]; then
  rm -rf "$DEST"
fi

# Pre-2026-09-20 installs deployed under the old id/directory name; clean
# that up too so a stale copy doesn't linger.
if [[ -L $OLD_DEST ]]; then
  rm "$OLD_DEST"
elif [[ -d $OLD_DEST ]]; then
  rm -rf "$OLD_DEST"
fi

echo "==> Uninstalled; stock omarchy.agents restored."
echo "    omarchy-pi-usage.timer remains on, feeding the pi tab."
