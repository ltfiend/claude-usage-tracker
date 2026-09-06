#!/usr/bin/env bash
# Install (or --uninstall) the claude-usage-tracker systemd user timer.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_DIR="$HOME/.config/systemd/user"
DATA_DIR="$HOME/.local/share/claude-usage-tracker"
UNITS=(claude-usage-tracker.service claude-usage-tracker.timer)

if [[ "${1:-}" == "--uninstall" ]]; then
    systemctl --user disable --now claude-usage-tracker.timer 2>/dev/null || true
    for unit in "${UNITS[@]}"; do
        rm -f "$UNIT_DIR/$unit"
    done
    systemctl --user daemon-reload
    echo "Uninstalled. Data left in $DATA_DIR"
    exit 0
fi

mkdir -p "$DATA_DIR" "$UNIT_DIR"
for unit in "${UNITS[@]}"; do
    install -m 644 "$REPO_DIR/systemd/$unit" "$UNIT_DIR/$unit"
done
systemctl --user daemon-reload
systemctl --user enable --now claude-usage-tracker.timer

echo
systemctl --user list-timers claude-usage-tracker.timer --no-pager
echo
echo "Data:    $DATA_DIR/{history.jsonl,cycles.csv}"
echo "Logs:    journalctl -t claude-usage-tracker"
