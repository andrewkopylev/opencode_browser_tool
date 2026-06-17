import { tool } from "@opencode-ai/plugin"
import path from "path"
import os from "node:os"
import { existsSync } from "fs"

function findScript(dir: string): string {
    const candidates = [
        path.join(dir, ".opencode/tools/browser.py"),
        path.join(dir, "browser.py"),
        path.join(os.homedir(), ".config", "opencode", "tools", "browser.py"),
    ]
    for (const p of candidates) {
        if (existsSync(p)) return p
    }
    return candidates[0]
}

async function callBrowser(cmd: string, extra: Record<string, any> = {}, directory: string) {
    let script = findScript(directory)
    const payload = JSON.stringify({ command: cmd, ...extra })

    let stdout = ""
    let stderr = ""
    let exitCode = 0

    try {
        const proc = Bun.spawn(["python3", script], {
            stdin: "pipe",
            stdout: "pipe",
            stderr: "pipe",
        })
        proc.stdin.write(payload)
        proc.stdin.end()

        exitCode = await proc.exited
        stdout = await new Response(proc.stdout).text()
        stderr = await new Response(proc.stderr).text()
    } catch (e: any) {
        return `browser_${cmd}: spawn failed: ${e.message || e}`
    }

    if (exitCode !== 0) {
        const detail = stderr.trim() || stdout.trim() || "(no output)"
        return `browser_${cmd}: exit ${exitCode}: ${detail}`
    }
    return stdout.trim()
}

export const open = tool({
    description:
        "Launch a new browser window. Returns a session_id needed for all other browser_* tools. " +
        "Use this first before any other browser operations.",
    args: {
        headless: tool.schema.boolean().optional().describe("Run in headless mode (no visible window). Default: false"),
    },
    async execute(args, context) {
        return await callBrowser("open", { headless: args.headless || false }, context.directory)
    },
})

export const close = tool({
    description: "Close a browser session and clean up its resources. Always call this when done.",
    args: {
        session_id: tool.schema.string().describe("Browser session ID from browser_open"),
    },
    async execute(args, context) {
        return await callBrowser("close", { session_id: args.session_id }, context.directory)
    },
})

export const navigate = tool({
    description:
        "Navigate the browser to a URL. Returns the page title after loading.",
    args: {
        session_id: tool.schema.string().describe("Browser session ID"),
        url: tool.schema.string().describe("Full URL to navigate to (include https://)"),
    },
    async execute(args, context) {
        return await callBrowser("navigate", { session_id: args.session_id, url: args.url }, context.directory)
    },
})

export const back = tool({
    description: "Go back in browser history. Returns page title.",
    args: { session_id: tool.schema.string().describe("Browser session ID") },
    async execute(args, context) {
        return await callBrowser("back", { session_id: args.session_id }, context.directory)
    },
})

export const forward = tool({
    description: "Go forward in browser history. Returns page title.",
    args: { session_id: tool.schema.string().describe("Browser session ID") },
    async execute(args, context) {
        return await callBrowser("forward", { session_id: args.session_id }, context.directory)
    },
})

export const refresh = tool({
    description: "Refresh/reload the current page.",
    args: { session_id: tool.schema.string().describe("Browser session ID") },
    async execute(args, context) {
        return await callBrowser("refresh", { session_id: args.session_id }, context.directory)
    },
})

export const click = tool({
    description:
        "Click an element on the page. Supports CSS selectors (default) or XPath. " +
        "Use 'selector_type' to change the strategy.",
    args: {
        session_id: tool.schema.string().describe("Browser session ID"),
        selector: tool.schema.string().describe("CSS selector (default) or XPath expression"),
        selector_type: tool.schema.enum(["css", "xpath"]).optional().describe("Default: css"),
        timeout_ms: tool.schema.number().optional().describe("Max wait time in ms. Default: 5000"),
    },
    async execute(args, context) {
        return await callBrowser("click", {
            session_id: args.session_id,
            selector: args.selector,
            selector_type: args.selector_type || "css",
            timeout_ms: args.timeout_ms || 5000,
        }, context.directory)
    },
})

export const type = tool({
    description:
        "Type text into an input field. Clears the field first by default.",
    args: {
        session_id: tool.schema.string().describe("Browser session ID"),
        selector: tool.schema.string().describe("CSS selector for the input field"),
        text: tool.schema.string().describe("Text to type"),
        selector_type: tool.schema.enum(["css", "xpath"]).optional().describe("Default: css"),
        clear_first: tool.schema.boolean().optional().describe("Clear existing text first. Default: true"),
    },
    async execute(args, context) {
        return await callBrowser("type", {
            session_id: args.session_id,
            selector: args.selector,
            text: args.text,
            selector_type: args.selector_type || "css",
            clear_first: args.clear_first !== false,
        }, context.directory)
    },
})

export const select = tool({
    description: "Select an option from a <select> dropdown by value or visible label.",
    args: {
        session_id: tool.schema.string().describe("Browser session ID"),
        selector: tool.schema.string().describe("CSS selector for the <select> element"),
        value: tool.schema.string().optional().describe("Option value attribute"),
        label: tool.schema.string().optional().describe("Visible text of the option"),
        selector_type: tool.schema.enum(["css", "xpath"]).optional().describe("Default: css"),
    },
    async execute(args, context) {
        return await callBrowser("select", {
            session_id: args.session_id,
            selector: args.selector,
            value: args.value || "",
            label: args.label || "",
            selector_type: args.selector_type || "css",
        }, context.directory)
    },
})

export const submit = tool({
    description: "Submit a form. If no selector given, presses Enter on body.",
    args: {
        session_id: tool.schema.string().describe("Browser session ID"),
        selector: tool.schema.string().optional().describe("CSS selector of an element inside the form"),
        selector_type: tool.schema.enum(["css", "xpath"]).optional().describe("Default: css"),
    },
    async execute(args, context) {
        return await callBrowser("submit", {
            session_id: args.session_id,
            selector: args.selector || "",
            selector_type: args.selector_type || "css",
        }, context.directory)
    },
})

export const scroll = tool({
    description:
        "Scroll the page. Directions: down, up, top, bottom. Use 'selector' to scroll to a specific element.",
    args: {
        session_id: tool.schema.string().describe("Browser session ID"),
        direction: tool.schema.enum(["down", "up", "top", "bottom"]).optional().describe("Default: down"),
        amount: tool.schema.number().optional().describe("Pixels for up/down. Default: 300"),
        selector: tool.schema.string().optional().describe("CSS selector to scroll into view (overrides direction)"),
    },
    async execute(args, context) {
        return await callBrowser("scroll", {
            session_id: args.session_id,
            direction: args.direction || "down",
            amount: args.amount || 300,
            selector: args.selector || "",
        }, context.directory)
    },
})

export const press_key = tool({
    description:
        "Press a keyboard key. Supports: ENTER, TAB, ESCAPE, BACKSPACE, DELETE, ARROW_UP/DOWN/LEFT/RIGHT, " +
        "PAGE_UP/DOWN, HOME, END, SPACE. Use 'selector' to send key to a specific element.",
    args: {
        session_id: tool.schema.string().describe("Browser session ID"),
        key: tool.schema.string().describe("Key name (e.g. ENTER, TAB, ESCAPE, ARROW_DOWN)"),
        selector: tool.schema.string().optional().describe("CSS selector to receive the key"),
    },
    async execute(args, context) {
        return await callBrowser("press_key", {
            session_id: args.session_id,
            key: args.key,
            selector: args.selector || "",
        }, context.directory)
    },
})

export const get_content = tool({
    description:
        "Get the text or HTML content of the page or a specific element. " +
        "Use format='text' for readable text (default), 'html' for raw HTML. " +
        "Use limit_chars to truncate large pages.",
    args: {
        session_id: tool.schema.string().describe("Browser session ID"),
        selector: tool.schema.string().optional().describe("CSS selector. Empty = full page"),
        format: tool.schema.enum(["text", "html"]).optional().describe("Default: text"),
        selector_type: tool.schema.enum(["css", "xpath"]).optional().describe("Default: css"),
        limit_chars: tool.schema.number().optional().describe("Max chars to return. 0 = no limit"),
    },
    async execute(args, context) {
        return await callBrowser("get_content", {
            session_id: args.session_id,
            selector: args.selector || "",
            format: args.format || "text",
            selector_type: args.selector_type || "css",
            limit_chars: args.limit_chars || 0,
        }, context.directory)
    },
})

export const get_url = tool({
    description: "Get the current page URL.",
    args: { session_id: tool.schema.string().describe("Browser session ID") },
    async execute(args, context) {
        return await callBrowser("get_url", { session_id: args.session_id }, context.directory)
    },
})

export const get_title = tool({
    description: "Get the current page title.",
    args: { session_id: tool.schema.string().describe("Browser session ID") },
    async execute(args, context) {
        return await callBrowser("get_title", { session_id: args.session_id }, context.directory)
    },
})

export const screenshot = tool({
    description:
        "Take a screenshot of the current page or a specific element. " +
        "Returns the file path to the saved PNG. Use the Read tool to view it.",
    args: {
        session_id: tool.schema.string().describe("Browser session ID"),
        selector: tool.schema.string().optional().describe("CSS selector of element. Empty = full page"),
    },
    async execute(args, context) {
        return await callBrowser("screenshot", {
            session_id: args.session_id,
            selector: args.selector || "",
        }, context.directory)
    },
})

export const execute_js = tool({
    description:
        "Execute arbitrary JavaScript code in the browser page context. " +
        "Use 'return' to get values back (e.g. 'return document.title').",
    args: {
        session_id: tool.schema.string().describe("Browser session ID"),
        code: tool.schema.string().describe("JavaScript code to execute"),
    },
    async execute(args, context) {
        return await callBrowser("execute_js", { session_id: args.session_id, code: args.code }, context.directory)
    },
})

export const wait = tool({
    description:
        "Wait for a specified time or until an element appears on the page. " +
        "Useful for pages that load content dynamically.",
    args: {
        session_id: tool.schema.string().describe("Browser session ID"),
        timeout_ms: tool.schema.number().optional().describe("Wait time in ms. Default: 5000"),
        selector: tool.schema.string().optional().describe("CSS selector to wait for. Empty = just sleep"),
        selector_type: tool.schema.enum(["css", "xpath"]).optional().describe("Default: css"),
    },
    async execute(args, context) {
        return await callBrowser("wait", {
            session_id: args.session_id,
            timeout_ms: args.timeout_ms || 5000,
            selector: args.selector || "",
            selector_type: args.selector_type || "css",
        }, context.directory)
    },
})

export const new_tab = tool({
    description: "Open a new browser tab and switch to it. Optionally navigate to a URL.",
    args: {
        session_id: tool.schema.string().describe("Browser session ID"),
        url: tool.schema.string().optional().describe("URL to open in the new tab (defaults to blank)"),
    },
    async execute(args, context) {
        return await callBrowser("new_tab", {
            session_id: args.session_id,
            url: args.url || "about:blank",
        }, context.directory)
    },
})

export const switch_tab = tool({
    description: "Switch to a different browser tab by index (0-based).",
    args: {
        session_id: tool.schema.string().describe("Browser session ID"),
        index: tool.schema.number().describe("Tab index: 0, 1, 2, ..."),
    },
    async execute(args, context) {
        return await callBrowser("switch_tab", {
            session_id: args.session_id,
            index: args.index,
        }, context.directory)
    },
})

export const list = tool({
    description: "List all active browser sessions with their URLs and titles.",
    args: {},
    async execute(args, context) {
        return await callBrowser("list", {}, context.directory)
    },
})
