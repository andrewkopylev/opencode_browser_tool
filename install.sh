#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# OpenCode Browser Tool — Linux/macOS installer
# ============================================================

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
WHITE="\033[1;37m"
NC="\033[0m" # No Color

CONFIG_SRC="browser_config.template.json"
CONFIG_DST="$HOME/.config/opencode/browser_config.json"
TOOLS_GLOBAL_DIR="$HOME/.config/opencode/tools"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  OpenCode Browser Tool Installer${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

# ---- Step 1: Check Python and dependencies ----
echo -e "${YELLOW}[1/4] Checking Python and dependencies...${NC}"
if ! command -v python3 &>/dev/null; then
    echo -e "${RED}Error: python3 not found in PATH.${NC}"
    echo "Install Python 3.8+ and try again."
    exit 1
fi

if ! python3 -c "import selenium" 2>/dev/null; then
    echo -e "${RED}  Selenium is not installed.${NC}"
    echo -e "${RED}  Install it with one of these commands:${NC}"
    echo -e "${RED}    pip install --user selenium${NC}"
    echo -e "${RED}    (add --break-system-packages if on modern Ubuntu/Debian)${NC}"
    echo -e "${RED}  Then re-run this installer.${NC}"
    exit 1
fi
echo -e "${GREEN}  Python + Selenium: OK${NC}"

# ---- Step 2: Check configuration ----
echo -e "${YELLOW}[2/4] Checking configuration...${NC}"

validate_config() {
    python3 - "$CONFIG_DST" 2>&1 << 'PYEOF'
import json, sys, os
cfg = json.load(open(sys.argv[1]))
errors = []
for key in ('chrome_binary', 'chromedriver_path'):
    val = cfg.get(key, '')
    if not val:
        errors.append(f'{key} is empty')
    elif val in ('/path/to/chrome', '/path/to/chromedriver', 'chrome', 'chromedriver'):
        errors.append(f'{key} is still a placeholder: {val}')
    elif not os.path.isfile(val):
        errors.append(f'{key} not found: {val}')
    elif not os.access(val, os.X_OK):
        errors.append(f'{key} is not executable: {val}')
if errors:
    for e in errors:
        print(f'ERROR:{e}')
    sys.exit(1)
print('OK')
PYEOF
}

if [ ! -f "$CONFIG_DST" ]; then
    if [ -f "$SCRIPT_DIR/browser_config.template.json" ]; then
        echo -e "${YELLOW}  Config not found. Creating from template...${NC}"
        mkdir -p "$(dirname "$CONFIG_DST")"
        cp "$SCRIPT_DIR/browser_config.template.json" "$CONFIG_DST"
    else
        echo -e "${YELLOW}  Config not found. Creating minimal...${NC}"
        mkdir -p "$(dirname "$CONFIG_DST")"
        cat > "$CONFIG_DST" << 'EOF'
{
  "chrome_binary": "/path/to/chrome",
  "chromedriver_path": "/path/to/chromedriver",
  "headless": false,
  "screenshot_dir": ""
}
EOF
    fi
    echo -e "${WHITE}  ========================================${NC}"
    echo -e "${WHITE}  ACTION REQUIRED${NC}"
    echo -e "${WHITE}  ========================================${NC}"
    echo -e "${WHITE}  1. Edit ${CONFIG_DST}${NC}"
    echo -e "${WHITE}  2. Set chrome_binary and chromedriver_path${NC}"
    echo -e "${WHITE}  3. Download matched pair from:${NC}"
    echo -e "${WHITE}     https://googlechromelabs.github.io/chrome-for-testing/${NC}"
    echo -e "${WHITE}  ========================================${NC}"
    echo ""
    read -rp "  Press Enter when ready (or Ctrl+C to abort)... "
fi

# Validate: must be valid JSON, no placeholders, binaries exist
val_output=$(validate_config) || true
if [ -z "$val_output" ] || echo "$val_output" | grep -q "^ERROR:"; then
    echo -e "${RED}  Config errors:${NC}"
    if [ -z "$val_output" ]; then
        echo -e "${RED}    - Python validation produced no output (crash?)${NC}"
    else
        echo "$val_output" | while read -r line; do
            if [[ "$line" == ERROR:* ]]; then
                echo -e "${RED}    - ${line#ERROR:}${NC}"
            else
                echo -e "${RED}    $line${NC}"
            fi
        done
    fi
    echo ""
    echo -e "${RED}  Fix ${CONFIG_DST} and re-run this installer.${NC}"
    exit 1
fi

echo -e "${GREEN}  Configuration: OK${NC}"

# ---- Step 3: Choose install target ----
echo -e "${YELLOW}[3/4] Choose installation target...${NC}"
echo "  (g) Global     — available in all projects  (~/.config/opencode/tools/)"
echo "  (l) Local      — this project only           (.opencode/tools/)"
read -rp "  Choice [g/l]: " choice

case "$choice" in
    l|L|local)
        TARGET_DIR="$SCRIPT_DIR/.opencode/tools"
        ;;
    *)
        TARGET_DIR="$TOOLS_GLOBAL_DIR"
        ;;
esac

mkdir -p "$TARGET_DIR"

# ---- Step 4: Copy files ----
echo -e "${YELLOW}[4/4] Installing...${NC}"
cp "$SCRIPT_DIR/browser.ts" "$TARGET_DIR/"
cp "$SCRIPT_DIR/browser.py" "$TARGET_DIR/"
chmod +x "$TARGET_DIR/browser.py"

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Installation complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "  Files installed to: ${CYAN}$TARGET_DIR${NC}"
echo -e "  Config at:          ${CYAN}$CONFIG_DST${NC}"
echo ""
echo -e "  ${YELLOW}Restart OpenCode for the tools to take effect.${NC}"
echo ""
