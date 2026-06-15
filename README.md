# OpenCode Browser Tool

A custom toolset for [OpenCode](https://opencode.ai) that gives AI agents full control of a Chrome browser via Selenium WebDriver.

## Use cases

### Testing

- **Functional testing** — walk through site pages, verify element visibility, headings, text, buttons and links
- **End-to-end testing** — full scenarios: login → fill form → submit → verify result
- **Regression testing** — compare screenshots of pages before/after deploy
- **Visual testing** — screenshots at different resolutions, layout verification

### Debugging

- **Frontend debugging** — open a page, execute JS in the console (`browser_execute_js`), inspect DOM, check for console errors
- **Session/cookie debugging** — reproduce bugs with specific cookies/localStorage via `browser_execute_js`
- **Error capture** — scrape error text from a page, screenshot the problematic state

### Automation

- **Web scraping** — extract text/data from pages, walk through pagination
- **Dynamic site scraping** — wait for JS rendering (`browser_wait`) then extract content
- **Availability monitoring** — periodically open a site, check title/URL, alert on failure
- **Landing page cataloging** — open N pages, screenshot them for a catalog
- **Form auto-filling** — account registration, questionnaire completion, application submission
- **Routine task automation** — login → export report → logout
- **Redirect verification** — open URL → `browser_get_url` → compare with expected
- **SEO checks** — open page → check title, meta, h1-h6 via `browser_get_content`

### Reporting & documentation

- **Bug demonstration** — "open page, click button X, screenshot" → ready-to-use bug report
- **Documentation assistance** — screenshot UI elements for user manuals

### Admin & internal tools

- **CRM/admin panel interaction** — login, create entity, verify result

In short: anything a person does manually in a browser, the agent can handle — from routine clicks to complex multi-step workflows.


## What it does

Provides **20 browser automation tools** that an OpenCode AI agent can use:

| Tool | Description |
|------|-------------|
| `browser_open` | Launch a new browser window → returns `session_id` |
| `browser_close` | Close a session and free resources |
| `browser_navigate` | Navigate to a URL |
| `browser_back` / `browser_forward` / `browser_refresh` | History navigation |
| `browser_click` | Click an element (CSS or XPath selector) |
| `browser_type` | Type text into an input field |
| `browser_select` | Select an option from a `<select>` dropdown |
| `browser_submit` | Submit a form |
| `browser_scroll` | Scroll page (down/up/top/bottom/to element) |
| `browser_press_key` | Press keyboard keys (Enter, Tab, Escape, arrows...) |
| `browser_get_content` | Get text or HTML content of page/element |
| `browser_get_url` | Get current URL |
| `browser_get_title` | Get page title |
| `browser_screenshot` | Take a screenshot → returns PNG file path |
| `browser_execute_js` | Execute arbitrary JavaScript in the page |
| `browser_wait` | Wait for element or timeout |
| `browser_new_tab` | Open a new browser tab |
| `browser_switch_tab` | Switch between tabs |
| `browser_list` | List all active browser sessions |


## Architecture

Each browser session runs as a long-lived daemon process that keeps the Selenium WebDriver alive. Tool calls communicate with the daemon over TCP (localhost). This design:

- Maintains browser state (cookies, sessions, localStorage) across tool calls
- Supports multiple concurrent browser sessions
- Survives OpenCode restarts (sessions persist until explicitly closed)

```
┌─────────────┐   JSON/stdin    ┌──────────────┐   TCP    ┌──────────────┐
│  OpenCode   │ ──────────────→ │ browser.py   │ ──────→  │  browser.py  │
│ (browser.ts)│ ←────────────── │(client mode) │ ←──────  │  (daemon)    │
└─────────────┘   stdout/text   └──────────────┘   JSON   └──────┬───────┘
                                                                 │
                                                         ┌───────▼───────┐
                                                         │  ChromeDriver │
                                                         │  + Chrome     │
                                                         └───────────────┘
```

## Requirements

- **Python 3.8+** with pip
- **Selenium** Python package
- **Chrome** browser (or Chromium)
- **ChromeDriver** + **Chrome** — download both from the official [Chrome for Testing](https://googlechromelabs.github.io/chrome-for-testing/) page. Always use a matched pair (same version) from this site.
- **OpenCode** (any recent version)

## Installation

### Quick install

```bash
# 1. Install Python dependencies
pip install -r requirements.txt

# 2. Configure paths
cp browser_config.template.json ~/.config/opencode/browser_config.json
# Edit ~/.config/opencode/browser_config.json with your Chrome/ChromeDriver paths

# 3. Run the installer
chmod +x install.sh
./install.sh
```

Or on Windows (PowerShell as Administrator):

```powershell
pip install -r requirements.txt
Copy-Item browser_config.template.json $env:USERPROFILE\.config\opencode\browser_config.json
# Edit the config file with your paths
powershell -ExecutionPolicy Bypass -File install.ps1
```

### Manual install

Copy the tool files to your OpenCode tools directory:

**Per-project** (only available in that project):
```bash
mkdir -p .opencode/tools/
cp browser.ts browser.py .opencode/tools/
```

**Global** (available in all projects):
```bash
mkdir -p ~/.config/opencode/tools/
cp browser.ts browser.py ~/.config/opencode/tools/
```

Then restart OpenCode.

## Configuration

Create `~/.config/opencode/browser_config.json`:

```json
{
  "chrome_binary": "/usr/bin/google-chrome",
  "chromedriver_path": "/usr/local/bin/chromedriver",
  "headless": false,
  "screenshot_dir": "/tmp/opencode_browser/screenshots"
}
```

| Field | Description |
|-------|-------------|
| `chrome_binary` | Path to Chrome/Chromium executable |
| `chromedriver_path` | Path to ChromeDriver executable |
| `headless` | Run in headless mode (no window). Default: `false` |
| `screenshot_dir` | Where screenshots are saved. Defaults to OS temp directory |

### Windows paths example

```json
{
  "chrome_binary": "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
  "chromedriver_path": "C:\\tools\\chromedriver.exe",
  "headless": false,
  "screenshot_dir": ""
}
```

## Usage

Once installed, restart OpenCode in a project directory. The AI agent will see the `browser_*` tools in its tool list and can use them freely.

Example interaction with the AI:

> **User:** Open example.com, take a screenshot, and tell me what's on the page.
>
> **Agent:** 
> - `browser_open({ headless: false })` → `session_id: "abc123"`
> - `browser_navigate({ session_id: "abc123", url: "https://example.com" })` → "Example Domain"
> - `browser_screenshot({ session_id: "abc123" })` → `/tmp/opencode_browser/screenshots/abc123_1712345678.png`
> - `browser_get_content({ session_id: "abc123", limit_chars: 500 })` → "Example Domain\nThis domain is for..."
> - `browser_close({ session_id: "abc123" })` → "Browser closed"

## Windows Compatibility

The tool is **fully cross-platform**. Key Windows-specific design choices:
- Socket-based IPC works identically on Windows and Unix
- Path handling uses `pathlib.Path` throughout

Windows users must ensure:
- Chrome and ChromeDriver `.exe` paths are correct in the config
- ChromeDriver matches the installed Chrome version
- Python is in `PATH`
- Execution policy allows running PowerShell scripts (or use manual install)

## Troubleshooting

**"Daemon start failed" or exit code 2**
- Check that `chrome_binary` and `chromedriver_path` in the config point to valid executables
- Run `python3 browser.py` manually and check the output

**"DevToolsActivePort file doesn't exist"**
- Chrome/ChromeDriver version mismatch. Download a matched pair from [Chrome for Testing](https://googlechromelabs.github.io/chrome-for-testing/).
- On Linux, ensure `--no-sandbox` is present (it is by default).

**"Session not found"**
- The session may have timed out or been cleaned up. Call `browser_open` again.

**"Address already in use"**
- Old daemon processes may still be running. Kill them manually:
  ```bash
  pkill -f "browser.py --daemon"
  pkill -f chromedriver
  ```

## License

MIT
