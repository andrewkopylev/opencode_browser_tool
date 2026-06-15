#!/usr/bin/env python3
"""Browser automation tool for OpenCode — daemon-based architecture."""

import sys
import json
import os
import time
import signal
import socket
import subprocess
import uuid
import tempfile
from pathlib import Path

from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.common.action_chains import ActionChains
from selenium.common.exceptions import (
    TimeoutException,
    NoSuchElementException,
    WebDriverException,
    InvalidSessionIdException,
)

IS_WINDOWS = sys.platform == "win32"
SESSION_FILE = Path(tempfile.gettempdir()) / "opencode_browser" / "sessions.json"
CONFIG_FILE = Path.home() / ".config/opencode/browser_config.json"

DEFAULT_CONFIG = {
    "chrome_binary": "chrome",
    "chromedriver_path": "chromedriver",
    "headless": False,
    "screenshot_dir": str(Path(tempfile.gettempdir()) / "opencode_browser" / "screenshots"),
}


def load_config():
    cfg = dict(DEFAULT_CONFIG)
    if CONFIG_FILE.exists():
        try:
            cfg.update(json.loads(CONFIG_FILE.read_text()))
        except (json.JSONDecodeError, IOError):
            pass
    return cfg


def load_sessions():
    if SESSION_FILE.exists():
        try:
            return json.loads(SESSION_FILE.read_text())
        except (json.JSONDecodeError, IOError):
            pass
    return {}


def save_sessions(sessions):
    SESSION_FILE.parent.mkdir(parents=True, exist_ok=True)
    SESSION_FILE.write_text(json.dumps(sessions, indent=2))


def get_next_port(sessions, start=9515):
    used_ports = {int(s["port"]) for s in sessions.values()}
    port = start
    while port in used_ports or not _port_free(port):
        port += 1
    return port


def _port_free(port):
    import socket as sock
    s = sock.socket(sock.AF_INET, sock.SOCK_STREAM)
    try:
        s.bind(("127.0.0.1", port))
        s.close()
        return True
    except OSError:
        return False


def start_chromedriver(cfg, port):
    env = os.environ.copy()
    proc = subprocess.Popen(
        [cfg["chromedriver_path"], f"--port={port}"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        env=env,
    )
    time.sleep(0.8)
    return proc


def create_driver(cfg):
    opts = webdriver.ChromeOptions()
    opts.binary_location = cfg["chrome_binary"]
    if cfg.get("headless"):
        opts.add_argument("--headless=new")
    opts.add_argument("--no-sandbox")
    opts.add_argument("--disable-dev-shm-usage")
    opts.add_argument("--disable-gpu")
    opts.add_argument("--remote-debugging-port=0")
    opts.add_argument("--disable-search-engine-choice-screen")
    opts.add_argument("--window-size=1280,900")
    return opts


def _find_element(driver, selector, selector_type="css"):
    by = By.CSS_SELECTOR if selector_type == "css" else By.XPATH
    return driver.find_element(by, selector)


def _ok(data):
    return json.dumps({"ok": True, "data": str(data) if not isinstance(data, dict) else data})


def _err(msg):
    return json.dumps({"ok": False, "error": str(msg)})


def handle_command(cfg, driver, cmd):
    c = cmd.get("command", "")
    try:
        if c == "navigate":
            driver.get(cmd["url"])
            return _ok(driver.title)
        elif c == "back":
            driver.back()
            return _ok(driver.title)
        elif c == "forward":
            driver.forward()
            return _ok(driver.title)
        elif c == "refresh":
            driver.refresh()
            return _ok("Refreshed")
        elif c == "click":
            sel = cmd.get("selector", "")
            sel_type = cmd.get("selector_type", "css")
            timeout = cmd.get("timeout_ms", 5000) / 1000.0
            by = By.CSS_SELECTOR if sel_type == "css" else By.XPATH
            el = WebDriverWait(driver, timeout).until(
                EC.element_to_be_clickable((by, sel))
            )
            el.click()
            return _ok(f"Clicked: {sel}")
        elif c == "type":
            sel = cmd["selector"]
            text = cmd["text"]
            sel_type = cmd.get("selector_type", "css")
            by = By.CSS_SELECTOR if sel_type == "css" else By.XPATH
            el = driver.find_element(by, sel)
            if cmd.get("clear_first", True):
                el.clear()
            el.send_keys(text)
            return _ok(f"Typed into: {sel}")
        elif c == "select":
            from selenium.webdriver.support.ui import Select
            sel = cmd["selector"]
            sel_type = cmd.get("selector_type", "css")
            by = By.CSS_SELECTOR if sel_type == "css" else By.XPATH
            el = driver.find_element(by, sel)
            s = Select(el)
            label = cmd.get("label", "")
            value = cmd.get("value", "")
            if label:
                s.select_by_visible_text(label)
            elif value:
                s.select_by_value(value)
            return _ok(f"Selected in: {sel}")
        elif c == "submit":
            sel = cmd.get("selector", "")
            if sel:
                sel_type = cmd.get("selector_type", "css")
                by = By.CSS_SELECTOR if sel_type == "css" else By.XPATH
                driver.find_element(by, sel).submit()
            else:
                driver.find_element(By.TAG_NAME, "body").send_keys(Keys.RETURN)
            return _ok("Submitted")
        elif c == "scroll":
            sel = cmd.get("selector", "")
            if sel:
                by = By.CSS_SELECTOR if cmd.get("selector_type", "css") == "css" else By.XPATH
                el = driver.find_element(by, sel)
                driver.execute_script("arguments[0].scrollIntoView({block:'center'});", el)
                return _ok(f"Scrolled to: {sel}")
            direction = cmd.get("direction", "down")
            amount = cmd.get("amount", 300)
            if direction == "down":
                driver.execute_script(f"window.scrollBy(0, {amount});")
            elif direction == "up":
                driver.execute_script(f"window.scrollBy(0, -{amount});")
            elif direction == "top":
                driver.execute_script("window.scrollTo(0, 0);")
            elif direction == "bottom":
                driver.execute_script("window.scrollTo(0, document.body.scrollHeight);")
            return _ok(f"Scrolled {direction}")
        elif c == "press_key":
            key = cmd["key"].upper()
            key_map = {
                "ENTER": Keys.ENTER, "TAB": Keys.TAB, "ESCAPE": Keys.ESCAPE, "ESC": Keys.ESCAPE,
                "BACKSPACE": Keys.BACKSPACE, "DELETE": Keys.DELETE,
                "ARROW_UP": Keys.ARROW_UP, "ARROW_DOWN": Keys.ARROW_DOWN,
                "ARROW_LEFT": Keys.ARROW_LEFT, "ARROW_RIGHT": Keys.ARROW_RIGHT,
                "PAGE_UP": Keys.PAGE_UP, "PAGE_DOWN": Keys.PAGE_DOWN,
                "HOME": Keys.HOME, "END": Keys.END, "SPACE": Keys.SPACE,
            }
            key_obj = key_map.get(key, key)
            sel = cmd.get("selector", "")
            if sel:
                driver.find_element(By.CSS_SELECTOR, sel).send_keys(key_obj)
            else:
                ActionChains(driver).send_keys(key_obj).perform()
            return _ok(f"Pressed: {key}")
        elif c == "get_content":
            sel = cmd.get("selector", "")
            fmt = cmd.get("format", "text")
            limit = cmd.get("limit_chars", 0)
            if sel:
                sel_type = cmd.get("selector_type", "css")
                by = By.CSS_SELECTOR if sel_type == "css" else By.XPATH
                el = driver.find_element(by, sel)
                content = el.get_attribute("innerHTML") if fmt == "html" else el.text
            else:
                content = driver.page_source if fmt == "html" else driver.find_element(By.TAG_NAME, "body").text
            if limit and len(content) > limit:
                content = content[:limit] + f"\n... [truncated, total {len(content)} chars]"
            return _ok(content)
        elif c == "get_url":
            return _ok(driver.current_url)
        elif c == "get_title":
            return _ok(driver.title)
        elif c == "screenshot":
            sel = cmd.get("selector", "")
            sd = Path(cfg.get("screenshot_dir", DEFAULT_CONFIG["screenshot_dir"]))
            sd.mkdir(parents=True, exist_ok=True)
            filename = f"{cmd.get('session_id','')}_{int(time.time())}.png"
            fp = sd / filename
            if sel:
                driver.find_element(By.CSS_SELECTOR, sel).screenshot(str(fp))
            else:
                driver.save_screenshot(str(fp))
            return _ok(str(fp))
        elif c == "execute_js":
            result = driver.execute_script(cmd["code"])
            return _ok(json.dumps(result, default=str))
        elif c == "wait":
            sel = cmd.get("selector", "")
            timeout = cmd.get("timeout_ms", 5000) / 1000.0
            if sel:
                sel_type = cmd.get("selector_type", "css")
                by = By.CSS_SELECTOR if sel_type == "css" else By.XPATH
                try:
                    WebDriverWait(driver, timeout).until(
                        EC.presence_of_element_located((by, sel))
                    )
                    return _ok(f"Element found: {sel}")
                except TimeoutException:
                    return _err(f"Timeout waiting for: {sel}")
            else:
                time.sleep(timeout)
                return _ok(f"Waited {cmd.get('timeout_ms', 5000)}ms")
        elif c == "new_tab":
            url = cmd.get("url", "about:blank")
            driver.execute_script(f"window.open('{url}', '_blank');")
            time.sleep(0.3)
            handles = driver.window_handles
            driver.switch_to.window(handles[-1])
            return _ok(f"New tab, {len(handles)} total, current: {driver.title}")
        elif c == "switch_tab":
            idx = cmd.get("index", 0)
            handles = driver.window_handles
            if 0 <= idx < len(handles):
                driver.switch_to.window(handles[idx])
                return _ok(f"Tab {idx}: {driver.title}")
            return _err(f"Invalid tab {idx}, have {len(handles)}")
        elif c == "quit":
            return _ok("bye")
        else:
            return _err(f"Unknown command: {c}")
    except NoSuchElementException:
        return _err(f"Element not found: {cmd.get('selector','')}")
    except TimeoutException:
        return _err(f"Timeout: {cmd.get('selector','')}")
    except WebDriverException as e:
        return _err(str(e))
    except Exception as e:
        return _err(str(e))


def run_daemon(cfg, port):
    cmd_port = get_next_port({}, port + 1)

    driver_proc = start_chromedriver(cfg, port)
    opts = create_driver(cfg)
    try:
        driver = webdriver.Remote(
            command_executor=f"http://127.0.0.1:{port}",
            options=opts,
        )
    except Exception as e:
        driver_proc.kill()
        print(json.dumps({"ok": False, "error": f"Failed to create driver: {e}"}))
        sys.exit(1)

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", cmd_port))
    server.listen(1)
    server.settimeout(300)

    print(json.dumps({"ok": True, "cmd_port": cmd_port, "driver_pid": driver_proc.pid}))
    sys.stdout.flush()

    try:
        while True:
            try:
                conn, _ = server.accept()
            except socket.timeout:
                continue
            try:
                data = b""
                while True:
                    chunk = conn.recv(65536)
                    if not chunk:
                        break
                    data += chunk
                    if len(data) > 10 * 1024 * 1024:
                        break
                    try:
                        json.loads(data.decode())
                        break
                    except json.JSONDecodeError:
                        continue
                cmd = json.loads(data.decode())
                if cmd.get("command") == "quit":
                    conn.sendall(json.dumps({"ok": True, "data": "bye"}).encode())
                    conn.close()
                    break
                result = handle_command(cfg, driver, cmd)
                conn.sendall(result.encode())
            except Exception as e:
                try:
                    conn.sendall(json.dumps({"ok": False, "error": str(e)}).encode())
                except Exception:
                    pass
            finally:
                try:
                    conn.close()
                except Exception:
                    pass
    finally:
        try:
            driver.quit()
        except Exception:
            pass
        try:
            driver_proc.kill()
        except Exception:
            pass
        try:
            server.close()
        except Exception:
            pass


def send_to_daemon(cmd_port, payload):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(15)
    sock.connect(("127.0.0.1", cmd_port))
    sock.sendall(json.dumps(payload).encode())
    sock.shutdown(socket.SHUT_WR)
    data = b""
    while True:
        chunk = sock.recv(65536)
        if not chunk:
            break
        data += chunk
    sock.close()
    return json.loads(data.decode())


def cmd_open(cfg, args):
    sessions = load_sessions()
    port = get_next_port(sessions)

    headless = cfg.get("headless", args.get("headless", False))
    env = os.environ.copy()
    env["HEADLESS"] = "true" if headless else "false"

    proc = subprocess.Popen(
        [sys.executable, __file__, "--daemon", str(port)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
    )
    out = proc.stdout.readline().decode().strip()
    if not out:
        err = proc.stderr.read().decode().strip()
        try:
            proc.kill()
        except Exception:
            pass
        return json.dumps({"ok": False, "error": f"Daemon start failed (stderr): {err}"})
    try:
        result = json.loads(out)
    except json.JSONDecodeError:
        return json.dumps({"ok": False, "error": f"Daemon output not JSON: {out}"})
    if not result.get("ok"):
        return json.dumps({"ok": False, "error": result.get("error", "Daemon start failed")})

    sid = uuid.uuid4().hex[:8]
    sessions[sid] = {
        "port": port,
        "cmd_port": result["cmd_port"],
        "driver_pid": result["driver_pid"],
        "daemon_pid": proc.pid,
    }
    save_sessions(sessions)
    return json.dumps({"session_id": sid, "headless": cfg.get("headless", False)})


def cmd_close(cfg, args):
    sid = args["session_id"]
    sessions = load_sessions()
    session = sessions.pop(sid, None)
    save_sessions(sessions)
    if not session:
        return "Session not found"
    try:
        send_to_daemon(session["cmd_port"], {"command": "quit"})
    except Exception:
        pass
    return "Browser closed"


def cmd_proxy(cfg, args):
    sid = args["session_id"]
    sessions = load_sessions()
    session = sessions.get(sid)
    if not session:
        return _err("Session not found")
    result = send_to_daemon(session["cmd_port"], args)
    if result.get("ok"):
        return result.get("data", "ok")
    return f"Error: {result.get('error', 'unknown')}"


def cmd_list(cfg, args):
    sessions = load_sessions()
    if not sessions:
        return "No active sessions"
    lines = []
    for sid, s in sessions.items():
        try:
            r = send_to_daemon(s["cmd_port"], {"command": "get_url"})
            url = r.get("data", "?") if r.get("ok") else "?"
            r2 = send_to_daemon(s["cmd_port"], {"command": "get_title"})
            title = r2.get("data", "?") if r2.get("ok") else "?"
            lines.append(f"{sid}: {title} — {url}")
        except Exception:
            lines.append(f"{sid}: (disconnected)")
    return "\n".join(lines)


CLIENT_COMMANDS = {
    "open": cmd_open,
    "close": cmd_close,
    "list": cmd_list,
}

PROXY_COMMANDS = {
    "navigate", "back", "forward", "refresh", "click", "type", "select",
    "submit", "scroll", "press_key", "get_content", "get_url", "get_title",
    "screenshot", "execute_js", "wait", "new_tab", "switch_tab",
}


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--daemon":
        port = int(sys.argv[2])
        cfg = load_config()
        cfg["headless"] = os.environ.get("HEADLESS", "false") == "True"
        run_daemon(cfg, port)
        return

    try:
        raw = sys.stdin.read().strip()
        if not raw:
            print("Error: no input")
            sys.exit(1)
        payload = json.loads(raw)
    except json.JSONDecodeError as e:
        print(f"Error: invalid JSON: {e}")
        sys.exit(1)

    cmd = payload.get("command", "")
    cfg = load_config()
    try:
        if cmd in CLIENT_COMMANDS:
            result = CLIENT_COMMANDS[cmd](cfg, payload)
            print(result)
        elif cmd in PROXY_COMMANDS:
            result = cmd_proxy(cfg, payload)
            print(result)
        else:
            print(f"Error: unknown command '{cmd}'")
            sys.exit(1)
    except InvalidSessionIdException:
        print("Error: browser session expired, open a new one")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
