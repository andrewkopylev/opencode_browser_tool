#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# OpenCode Browser Tool — Linux/macOS installer
# ============================================================

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
NC="\033[0m" # No Color

CONFIG_SRC="browser_config.template.json"
CONFIG_DST="$HOME/.config/opencode/browser_config.json"
TOOLS_GLOBAL_DIR="$HOME/.config/opencode/tools"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  OpenCode Browser Tool Installer${NC}"
echo -e "${CYAN}============================================${NC}"
echo ""

# ---- Step 1: Check Python ----
echo -e "${YELLOW}[1/4] Checking Python...${NC}"
if ! command -v python3 &>/dev/null; then
    echo -e "${RED}Error: python3 not found in PATH.${NC}"
    echo "Install Python 3.8+ and try again."
    exit 1
fi
echo -e "${GREEN}  Python: OK${NC}"

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
    echo -e "${RED}  ========================================${NC}"
    echo -e "${RED}  ACTION REQUIRED${NC}"
    echo -e "${RED}  ========================================${NC}"
    echo -e "${RED}  1. Edit ${CONFIG_DST}${NC}"
    echo -e "${RED}  2. Set chrome_binary and chromedriver_path${NC}"
    echo -e "${RED}  3. Download matched pair from:${NC}"
    echo -e "${RED}     https://googlechromelabs.github.io/chrome-for-testing/${NC}"
    echo -e "${RED}  ========================================${NC}"
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

# Create venv and install selenium
echo -e "  Setting up Python virtual environment..."
VENV_DIR="$TARGET_DIR/.browser_venv"
if [ -d "$VENV_DIR" ]; then
    rm -rf "$VENV_DIR"
fi
python3 -m venv "$VENV_DIR"
if [ -f "$VENV_DIR/bin/python3" ]; then
    VENV_PYTHON="$VENV_DIR/bin/python3"
elif [ -f "$VENV_DIR/bin/python" ]; then
    VENV_PYTHON="$VENV_DIR/bin/python"
else
    echo -e "${RED}  Error: venv creation failed — Python binary not found.${NC}"
    exit 1
fi
"$VENV_PYTHON" -m pip install -r "$SCRIPT_DIR/requirements.txt" 2>&1 | grep -v "^Requirement already satisfied" || true
echo -e "${GREEN}  Venv + Selenium: OK${NC}"

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
