/**
 * Ask Mode Extension
 *
 * A read-only Q&A mode that disallows file editing but allows the agent
 * to run shell commands for exploration. Perfect for asking questions about
 * a codebase without risking any modifications.
 *
 * When active, the edit and write tools are blocked, and the agent receives
 * context explaining it is in "ask mode" — it should only answer questions,
 * not create or modify files.
 *
 * Usage:
 *   pi --ask                    # Start in ask mode via flag
 *   /ask                        # Toggle ask mode from within pi
 *   Ctrl+Alt+A                  # Toggle ask mode via shortcut
 *
 * Allowed tools: read, bash, grep, find, ls
 * Blocked tools: edit, write
 */

import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";
import { Key } from "@mariozechner/pi-tui";

const ASK_MODE_TOOLS = ["read", "bash", "grep", "find", "ls"];
const NORMAL_MODE_TOOLS = ["read", "bash", "edit", "write"];

export default function askModeExtension(pi: ExtensionAPI): void {
	let askModeEnabled = false;

	// ── CLI Flag ──────────────────────────────────────────────────────────
	pi.registerFlag("ask", {
		description: "Start in ask mode (read-only Q&A, no file editing)",
		type: "boolean",
		default: false,
	});

	// ── Status & UI ───────────────────────────────────────────────────────
	function updateStatus(ctx: ExtensionContext): void {
		if (askModeEnabled) {
			ctx.ui.setStatus(
				"ask-mode",
				ctx.ui.theme.fg("accent", "💬 ask mode"),
			);
		} else {
			ctx.ui.setStatus("ask-mode", undefined);
		}
	}

	// ── Toggle ────────────────────────────────────────────────────────────
	function toggleAskMode(ctx: ExtensionContext): void {
		askModeEnabled = !askModeEnabled;

		if (askModeEnabled) {
			pi.setActiveTools(ASK_MODE_TOOLS);
			ctx.ui.notify(
				`Ask mode enabled. Tools: ${ASK_MODE_TOOLS.join(", ")}`,
				"info",
			);
		} else {
			pi.setActiveTools(NORMAL_MODE_TOOLS);
			ctx.ui.notify(
				"Ask mode disabled. Full access restored.",
				"info",
			);
		}
		updateStatus(ctx);
		persistState();
	}

	// ── Persistence ───────────────────────────────────────────────────────
	function persistState(): void {
		pi.appendEntry("ask-mode", { enabled: askModeEnabled });
	}

	// ── Command ───────────────────────────────────────────────────────────
	pi.registerCommand("ask", {
		description: "Toggle ask mode (read-only Q&A, no file editing)",
		handler: async (_args, ctx) => toggleAskMode(ctx),
	});

	// ── Shortcut ──────────────────────────────────────────────────────────
	pi.registerShortcut(Key.ctrlAlt("a"), {
		description: "Toggle ask mode",
		handler: async (ctx) => toggleAskMode(ctx),
	});

	// ── Block edit/write tool calls ───────────────────────────────────────
	pi.on("tool_call", async (event) => {
		if (!askModeEnabled) return;

		if (event.toolName === "edit" || event.toolName === "write") {
			return {
				block: true,
				reason: `Ask mode: "${event.toolName}" is disabled. You are in ask mode — only answering questions is allowed, no file modifications. Use /ask to disable ask mode first.`,
			};
		}
	});

	// ── Inject ask mode context ───────────────────────────────────────────
	pi.on("before_agent_start", async (event) => {
		if (!askModeEnabled) return;

		return {
			systemPrompt: `${event.systemPrompt}

[ASK MODE ACTIVE]
You are currently in **ask mode** — a restricted, read-only Q&A mode.

Purpose: You are here to answer questions about the codebase, explain code, debug issues, and explore the project. You must NOT create, modify, or delete any files.

What you CAN do:
- Read any file using the read tool
- Run shell commands using bash (for exploration: git log, git diff, ls, cat, grep, find, etc.)
- Search with grep, find, and ls
- Answer questions, explain concepts, suggest solutions

What you CANNOT do:
- Edit files (edit tool is disabled)
- Write/create files (write tool is disabled)
- Make any changes to the filesystem

If the user asks you to make changes, explain what you would do but do not attempt to modify files. Suggest they disable ask mode with /ask if they want you to proceed with changes.`,
		};
	});

	// ── Filter out stale ask mode context when disabled ───────────────────
	pi.on("context", async (event) => {
		if (askModeEnabled) return;

		// No special filtering needed — the system prompt is already
		// injected fresh each turn via before_agent_start
		return undefined;
	});

	// ── Restore state on session start/resume ─────────────────────────────
	pi.on("session_start", async (_event, ctx) => {
		// Check --ask flag
		if (pi.getFlag("ask") === true) {
			askModeEnabled = true;
		}

		// Restore persisted state (only if no flag override)
		if (!askModeEnabled) {
			const entries = ctx.sessionManager.getEntries();
			const askModeEntry = entries
				.filter(
					(e: { type: string; customType?: string }) =>
						e.type === "custom" && e.customType === "ask-mode",
				)
				.pop() as { data?: { enabled: boolean } } | undefined;

			if (askModeEntry?.data?.enabled) {
				askModeEnabled = true;
			}
		}

		if (askModeEnabled) {
			pi.setActiveTools(ASK_MODE_TOOLS);
		}
		updateStatus(ctx);
	});
}
