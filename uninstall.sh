#!/usr/bin/env bash
# Uninstall Agents Monitor: remove it from the bar and restore the stock
# omarchy.agents widget. The omarchy-pi-usage.timer stays enabled (option 2),
# so the pi tab keeps refreshing even under the stock widget.

set -euo pipefail

DEST="$HOME/.config/omarchy/plugins/ptr.agents-monitor"

omarchy plugin disable ptr.agents-monitor 2>/dev/null || true
omarchy plugin enable omarchy.agents --after omarchy.tailscale

# Z.ai usage timer: off with the plugin (its collector lives in it).
systemctl --user disable --now omarchy-zai-usage.timer 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/omarchy-zai-usage.service" \
      "$HOME/.config/systemd/user/omarchy-zai-usage.timer"

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

echo "==> Uninstalled; stock omarchy.agents restored."
echo "    omarchy-pi-usage.timer remains on, feeding the pi tab."
