#!/usr/bin/env bash
set -euo pipefail

CURSOR_DIR="${HOME}/.cursor"
RULES_DIR="${CURSOR_DIR}/rules"
HOOKS_DIR="${CURSOR_DIR}/hooks"
HOOKS_JSON="${CURSOR_DIR}/hooks.json"

REPO_URL="https://raw.githubusercontent.com/harshm121/glassbox/main"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { printf "${GREEN}[glassbox]${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}[glassbox]${NC} %s\n" "$1"; }

command -v python3 >/dev/null 2>&1 || { warn "python3 is required but not installed."; exit 1; }
command -v git >/dev/null 2>&1 || { warn "git is required but not installed."; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info "Installing Glassbox..."

mkdir -p "$RULES_DIR" "$HOOKS_DIR"

if [ -f "$SCRIPT_DIR/glassbox.mdc" ]; then
    cp "$SCRIPT_DIR/glassbox.mdc" "$RULES_DIR/glassbox.mdc"
else
    curl -fsSL "$REPO_URL/glassbox.mdc" -o "$RULES_DIR/glassbox.mdc"
fi
info "Rule installed -> $RULES_DIR/glassbox.mdc"

if [ -f "$SCRIPT_DIR/check-vis-md.sh" ]; then
    cp "$SCRIPT_DIR/check-vis-md.sh" "$HOOKS_DIR/check-vis-md.sh"
else
    curl -fsSL "$REPO_URL/check-vis-md.sh" -o "$HOOKS_DIR/check-vis-md.sh"
fi
chmod +x "$HOOKS_DIR/check-vis-md.sh"
info "Hook script installed -> $HOOKS_DIR/check-vis-md.sh"

HOOK_ENTRY='{
  "command": "bash ./hooks/check-vis-md.sh",
  "loop_limit": 2,
  "timeout": 30
}'

if [ ! -f "$HOOKS_JSON" ]; then
    cat > "$HOOKS_JSON" << 'HOOKEOF'
{
  "version": 1,
  "hooks": {
    "stop": [
      {
        "command": "bash ./hooks/check-vis-md.sh",
        "loop_limit": 2,
        "timeout": 30
      }
    ]
  }
}
HOOKEOF
    info "Hook config created -> $HOOKS_JSON"
else
    if grep -q "check-vis-md.sh" "$HOOKS_JSON"; then
        info "Hook config already contains glassbox entry, skipping."
    else
        warn "hooks.json already exists at $HOOKS_JSON"
        warn "Please manually add this entry to the \"stop\" array:"
        echo ""
        echo "  $HOOK_ENTRY"
        echo ""
    fi
fi

echo ""
info "Glassbox installed successfully!"
info "Restart Cursor (or open a new window) to activate."
echo ""
info "How it works:"
info "  1. Ask Cursor to edit code — it will auto-generate .vis.md files"
info "  2. Open any .vis.md and press Cmd+Shift+V to see the diagrams"
info "  3. The .vis/ directory is safe to commit to git"
