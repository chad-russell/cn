/**
 * /ask — Sub-agent slash command
 *
 * Spawns a fresh `pi` subprocess with an isolated context window to research
 * a question, then injects the answer back into the current session as a
 * display-only custom message (no agent loop triggered).
 *
 * The answer is visible to the LLM on subsequent turns.
 */

import { spawn } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { BorderedLoader, getMarkdownTheme } from "@mariozechner/pi-coding-agent";
import { Container, Markdown, Spacer, Text } from "@mariozechner/pi-tui";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function truncate(text: string, maxLen: number): string {
    return text.length <= maxLen ? text : text.slice(0, maxLen) + "...";
}

function formatTokens(n: number): string {
    if (n < 1_000) return String(n);
    if (n < 10_000) return `${(n / 1_000).toFixed(1)}k`;
    return `${Math.round(n / 1_000)}k`;
}

/** Build the system prompt that the sub-agent will receive. */
function buildSystemPrompt(sessionFile: string | undefined, branch: Array<any>): string {
    const lines: string[] = [
        "You are a focused research sub-agent spawned from a parent conversation.",
        "Answer the user's question concisely and accurately using your tools.",
        "Be thorough in your research but concise in your final answer.",
        "Do NOT narrate your research process — just provide the answer.",
    ];

    if (sessionFile) {
        lines.push(
            "",
            `Parent session file: ${sessionFile}`,
            "This is a JSONL file — each line is a JSON object. You can read it for the full conversation history if you need more context.",
        );
    }

    // Inline the last few user messages so the sub-agent has immediate context
    // without needing to parse the JSONL file.
    const recentUserTexts = branch
        .filter((e: any) => e.type === "message" && e.message?.role === "user")
        .slice(-5)
        .map((e: any) => {
            const c = e.message.content;
            if (typeof c === "string") return c;
            if (Array.isArray(c)) return c.filter((p: any) => p.type === "text").map((p: any) => p.text).join(" ");
            return "";
        })
        .filter(Boolean);

    if (recentUserTexts.length > 0) {
        lines.push("", "Recent conversation from parent session:");
        for (const msg of recentUserTexts) {
            lines.push(`  > ${truncate(msg, 300)}`);
        }
    }

    return lines.join("\n");
}

/** Extract the last assistant text from a list of messages. */
function getFinalOutput(messages: Array<any>): string {
    for (let i = messages.length - 1; i >= 0; i--) {
        const msg = messages[i];
        if (msg.role === "assistant") {
            for (const part of msg.content ?? []) {
                if (part.type === "text") return part.text;
            }
        }
    }
    return "";
}

/** Determine how to invoke the pi binary from within a running pi process. */
function getPiInvocation(args: string[]): { command: string; args: string[] } {
    const currentScript = process.argv[1];
    const isBunVirtual = currentScript?.startsWith("/$bunfs/root/");
    if (currentScript && !isBunVirtual && fs.existsSync(currentScript)) {
        return { command: process.execPath, args: [currentScript, ...args] };
    }
    const execName = path.basename(process.execPath).toLowerCase();
    if (!/^(node|bun)(\.exe)?$/.test(execName)) {
        return { command: process.execPath, args };
    }
    return { command: "pi", args };
}

// ---------------------------------------------------------------------------
// Sub-agent runner
// ---------------------------------------------------------------------------

interface UsageStats {
    input: number;
    output: number;
    cost: number;
    turns: number;
}

interface SubAgentResult {
    answer: string;
    error?: string;
    usage?: UsageStats;
    model?: string;
}

async function runSubAgent(
    question: string,
    systemPromptFile: string,
    model: { provider: string; id: string } | undefined,
    cwd: string,
    signal?: AbortSignal,
): Promise<SubAgentResult> {
    const args: string[] = [
        "--mode", "json",
        "-p",
        "--no-session",
        "--tools", "read,bash,edit,write,grep,find,ls",
        "--append-system-prompt", systemPromptFile,
    ];

    if (model) {
        args.push("--model", `${model.provider}/${model.id}`);
    }

    args.push(question);

    return new Promise<SubAgentResult>((resolve) => {
        const inv = getPiInvocation(args);
        const proc = spawn(inv.command, inv.args, {
            cwd,
            shell: false,
            stdio: ["ignore", "pipe", "pipe"],
        });

        let wasAborted = false;

        // Wire up external abort signal (e.g. from BorderedLoader)
        if (signal) {
            const onAbort = () => {
                wasAborted = true;
                proc.kill();
            };
            if (signal.aborted) { onAbort(); }
            else { signal.addEventListener("abort", onAbort, { once: true }); }
            proc.on("close", () => { signal.removeEventListener("abort", onAbort); });
        }

        const messages: Array<any> = [];
        let stderr = "";
        let buffer = "";

        const usage: UsageStats = { input: 0, output: 0, cost: 0, turns: 0 };
        let lastModel: string | undefined;

        const processLine = (line: string) => {
            if (!line.trim()) return;
            let event: any;
            try { event = JSON.parse(line); } catch { return; }

            if (event.type === "message_end" && event.message) {
                const msg = event.message;
                messages.push(msg);

                if (msg.role === "assistant") {
                    usage.turns++;
                    if (msg.usage) {
                        usage.input += msg.usage.input || 0;
                        usage.output += msg.usage.output || 0;
                        usage.cost += msg.usage.cost?.total || 0;
                    }
                    if (msg.model && !lastModel) lastModel = msg.model;
                }
            }
        };

        proc.stdout.on("data", (data: Buffer) => {
            buffer += data.toString();
            const lines = buffer.split("\n");
            buffer = lines.pop() || "";
            for (const line of lines) processLine(line);
        });

        proc.stderr.on("data", (data: Buffer) => {
            stderr += data.toString();
        });

        proc.on("close", (code) => {
            if (buffer.trim()) processLine(buffer);

            if (wasAborted) {
                resolve({ answer: "", error: "Aborted", usage, model: lastModel });
                return;
            }

            if (code !== 0) {
                resolve({ answer: "", error: stderr?.trim() || `Exit code ${code}`, usage, model: lastModel });
                return;
            }

            resolve({ answer: getFinalOutput(messages), usage, model: lastModel });
        });

        proc.on("error", (err) => {
            resolve({ answer: "", error: err.message });
        });
    });
}

// ---------------------------------------------------------------------------
// Extension
// ---------------------------------------------------------------------------

export default function (pi: ExtensionAPI) {
    // ------------------------------------------------------------------
    // /ask command
    // ------------------------------------------------------------------
    pi.registerCommand("ask", {
        description: "Ask a sub-agent a question (fresh context, answer injected into conversation)",

        handler: async (args, ctx) => {
            const question = args?.trim();
            if (!question) {
                ctx.ui.notify("Usage: /ask <question>", "warning");
                return;
            }

            // Wait for any in-flight agent work to settle.
            await ctx.waitForIdle();

            const sessionFile = ctx.sessionManager.getSessionFile();
            const branch = ctx.sessionManager.getBranch();
            const model = ctx.model;

            const systemPrompt = buildSystemPrompt(sessionFile, branch);

            // Write the system prompt to a temp file that we pass to the child.
            const tmpDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), "pi-ask-"));
            const tmpFile = path.join(tmpDir, "system-prompt.md");

            try {
                await fs.promises.writeFile(tmpFile, systemPrompt, { encoding: "utf-8", mode: 0o600 });

                // Show a bordered spinner while the sub-agent works.
                const result = await ctx.ui.custom<SubAgentResult | null>((tui, theme, _kb, done) => {
                    const loader = new BorderedLoader(
                        tui,
                        theme,
                        `Sub-agent researching: ${truncate(question, 60)}`,
                    );
                    loader.onAbort = () => done(null);

                    runSubAgent(question, tmpFile, model, ctx.cwd, loader.signal)
                        .then((r) => done(r))
                        .catch((err) => done({ answer: "", error: err.message }));

                    return loader;
                });

                if (result === null) {
                    ctx.ui.notify("Sub-agent cancelled", "info");
                    return;
                }

                if (result.error) {
                    ctx.ui.notify(`Sub-agent failed: ${result.error}`, "error");
                    return;
                }

                // Inject the answer as a custom message.
                // - display: true   → visible in the TUI
                // - triggerTurn: false → does NOT start an agent loop
                // The message lives in the session so the LLM sees it on the next turn.
                pi.sendMessage(
                    {
                        customType: "ask-result",
                        content: result.answer || "(no answer)",
                        display: true,
                        details: {
                            question,
                            usage: result.usage,
                            model: result.model,
                        },
                    },
                    { triggerTurn: false },
                );
            } finally {
                try { await fs.promises.unlink(tmpFile); } catch { /* noop */ }
                try { await fs.promises.rmdir(tmpDir); } catch { /* noop */ }
            }
        },
    });

    // ------------------------------------------------------------------
    // Custom renderer for ask-result messages
    // ------------------------------------------------------------------
    pi.registerMessageRenderer("ask-result", (message, options, theme) => {
        const mdTheme = getMarkdownTheme();
        const container = new Container();
        const question = message.details?.question || "";
        const usage = message.details?.usage as UsageStats | undefined;
        const modelUsed = message.details?.model as string | undefined;
        const content = typeof message.content === "string" ? message.content : "";

        // Header ───────────────────────────────────────────
        let header = theme.fg("accent", "╭─ /ask ");
        header += theme.fg("dim", truncate(question, 90));
        container.addChild(new Text(header, 0, 0));
        container.addChild(new Spacer(1));

        // Body ─────────────────────────────────────────────
        if (options.expanded) {
            container.addChild(new Markdown(content, 0, 0, mdTheme));
        } else {
            const previewLines = content.split("\n").slice(0, 10).join("\n");
            container.addChild(new Markdown(previewLines, 0, 0, mdTheme));
            if (content.split("\n").length > 10) {
                container.addChild(new Text(theme.fg("muted", "(Ctrl+O to expand)"), 0, 0));
            }
        }

        // Footer ───────────────────────────────────────────
        container.addChild(new Spacer(1));
        let footer = theme.fg("dim", "╰─ sub-agent result");
        if (usage) {
            const parts: string[] = [];
            if (usage.turns) parts.push(`${usage.turns} turn${usage.turns > 1 ? "s" : ""}`);
            if (usage.input) parts.push(`↑${formatTokens(usage.input)}`);
            if (usage.output) parts.push(`↓${formatTokens(usage.output)}`);
            if (usage.cost) parts.push(`$${usage.cost.toFixed(4)}`);
            if (parts.length) footer += " · " + parts.join(" ");
        }
        if (modelUsed) footer += theme.fg("muted", ` · ${modelUsed}`);
        container.addChild(new Text(footer, 0, 0));

        return container;
    });
}
