/**
 * Real-time token speed monitor.
 *
 * Status line:  ⚡ 73.2 t/s avg 90.3
 *
 * On by default. `/speed toggle` switches it and saves the choice to
 * `~/.pi/agent/settings.json` under `tokenSpeed.enabled`, so it survives
 * restarts (`/speed on`, `/speed off`, `/speed status` also work).
 *
 * Counts are estimated from stream deltas (~4 chars per token, CJK ~1 token per
 * char) and calibrated against the provider's reported usage at message_end.
 */

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { homedir } from "node:os";
import { type AssistantMessage } from "@earendil-works/pi-ai";
import { withFileMutationQueue, type ExtensionAPI, type ExtensionContext, type Theme } from "@earendil-works/pi-coding-agent";

const STATUS_KEY = "token-speed";
const SETTINGS_SECTION = "tokenSpeed";
const WINDOW_SECS = 3;
const RENDER_MS = 250;

interface Sample {
	t: number;
	tokens: number;
}

interface MessageState {
	firstDeltaMs: number;
	lastDeltaMs: number;
	estimated: number;
	reported: number;
	total: number;
}

function clamp(value: number, min: number, max: number): number {
	return Math.min(max, Math.max(min, value));
}

function isCjk(code: number): boolean {
	return (
		(code >= 0x1100 && code <= 0x115f) ||
		(code >= 0x2e80 && code <= 0xa4cf) ||
		(code >= 0xac00 && code <= 0xd7a3) ||
		(code >= 0xf900 && code <= 0xfaff) ||
		(code >= 0xfe30 && code <= 0xfe4f) ||
		(code >= 0xff00 && code <= 0xff65) ||
		(code >= 0x20000 && code <= 0x2fa1f)
	);
}

/** Rough token estimate: CJK counts as one token, other characters as a quarter. */
function estimateTokens(text: string): number {
	let tokens = 0;
	for (let i = 0; i < text.length; i++) {
		const code = text.charCodeAt(i);
		if (code >= 0xd800 && code <= 0xdbff) {
			tokens += 1;
			i++;
			continue;
		}
		tokens += isCjk(code) ? 1 : 0.25;
	}
	return tokens;
}

/** Best-effort output-token read from a raw provider stream event (shapes vary by API). */
function extractOutputTokens(data: unknown): number | undefined {
	if (!data || typeof data !== "object") return undefined;
	const record = data as Record<string, unknown>;
	let usage: Record<string, unknown> | undefined;
	if (record.usage && typeof record.usage === "object") {
		usage = record.usage as Record<string, unknown>;
	} else if (record.delta && typeof record.delta === "object") {
		const nested = (record.delta as Record<string, unknown>).usage;
		if (nested && typeof nested === "object") usage = nested as Record<string, unknown>;
	}
	if (!usage) return undefined;
	for (const key of ["output_tokens", "completion_tokens", "output", "generated_tokens"]) {
		const value = usage[key];
		if (typeof value === "number" && Number.isFinite(value)) return value;
	}
	return undefined;
}

function fmtTps(value: number): string {
	return value >= 100 ? value.toFixed(0) : value.toFixed(1);
}

function settingsPath(): string {
	const agentDir = process.env.PI_CODING_AGENT_DIR || join(homedir(), ".pi", "agent");
	return join(agentDir, "settings.json");
}

export default function (pi: ExtensionAPI) {
	let enabled = true;

	const samples: Sample[] = [];
	const stats = { tokens: 0, genMs: 0 };

	let calib = 1;
	let lastRenderAt = 0;
	let lastCtx: ExtensionContext | undefined;
	let msg: MessageState | undefined;

	function reset(): void {
		samples.length = 0;
		stats.tokens = 0;
		stats.genMs = 0;
		calib = 1;
		msg = undefined;
	}

	/** Wall time actually spent generating, including the in-flight message. */
	function generatingMs(now: number): number {
		if (msg?.firstDeltaMs) return stats.genMs + Math.max(0, now - msg.firstDeltaMs);
		return stats.genMs;
	}

	function averageTps(now: number): number {
		const ms = generatingMs(now);
		return ms > 0 ? stats.tokens / (ms / 1000) : 0;
	}

	/** Live rate over the sliding window; pruned at render time to keep the hot path cheap. */
	function windowTps(now: number): number {
		const cutoff = now - WINDOW_SECS * 1000;
		while (samples.length > 0 && samples[0].t < cutoff) samples.shift();
		if (samples.length === 0) return 0;
		let sum = 0;
		for (const sample of samples) sum += sample.tokens;
		return sum / clamp((now - samples[0].t) / 1000, 0.5, WINDOW_SECS);
	}

	function addTokens(tokens: number, now: number): void {
		if (tokens <= 0) return;
		stats.tokens += tokens;
		samples.push({ t: now, tokens });
		if (samples.length > 5000) samples.shift();
	}

	/** Grow the message total to `target`, counting only newly seen tokens (no double counting). */
	function bumpMessage(target: number, now: number): void {
		if (!msg || target <= msg.total) return;
		addTokens(target - msg.total, now);
		msg.total = target;
	}

	function statusLine(theme: Theme, now: number): string {
		const live = windowTps(now);
		return `${theme.fg(live > 0 ? "accent" : "muted", `⚡ ${fmtTps(live)} t/s`)} ${theme.fg("dim", `avg ${fmtTps(averageTps(now))}`)}`;
	}

	function showStatus(ctx: ExtensionContext): void {
		if (!ctx.hasUI) return;
		ctx.ui.setStatus(STATUS_KEY, enabled ? statusLine(ctx.ui.theme, Date.now()) : undefined);
	}

	function refresh(force = false): void {
		const ctx = lastCtx;
		if (!ctx || !enabled || !ctx.hasUI) return;
		const now = Date.now();
		if (!force && now - lastRenderAt < RENDER_MS) return;
		lastRenderAt = now;
		showStatus(ctx);
	}

	/** Save the choice to settings.json, merging into the existing file. */
	async function persist(ctx: ExtensionContext): Promise<void> {
		const path = settingsPath();
		if (!existsSync(dirname(path))) return; // do not create the config dir from an extension
		try {
			await withFileMutationQueue(path, async () => {
				let settings: Record<string, unknown> = {};
				if (existsSync(path)) {
					try {
						const parsed: unknown = JSON.parse(readFileSync(path, "utf-8"));
						if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) settings = parsed as Record<string, unknown>;
					} catch {
						settings = {};
					}
				}
				const section = settings[SETTINGS_SECTION];
				const block = section && typeof section === "object" && !Array.isArray(section) ? (section as Record<string, unknown>) : {};
				block.enabled = enabled;
				settings[SETTINGS_SECTION] = block;
				writeFileSync(path, JSON.stringify(settings, null, 2));
			});
		} catch (error) {
			if (ctx.hasUI) ctx.ui.notify(`Could not save token speed setting: ${error instanceof Error ? error.message : String(error)}`, "warning");
		}
	}

	async function setEnabled(ctx: ExtensionContext, next: boolean): Promise<void> {
		enabled = next;
		if (!ctx.hasUI) return;
		showStatus(ctx);
		await persist(ctx);
		ctx.ui.notify(`Token speed ${enabled ? "on" : "off"} (saved)`, "info");
	}

	pi.registerCommand("speed", {
		description: "Toggle the token speed meter; the choice is saved to settings.json",
		getArgumentCompletions: (prefix) => ["toggle", "on", "off", "status"].filter((item) => item.startsWith(prefix)).map((item) => ({ value: item, label: item })),
		handler: async (args, ctx) => {
			const arg = args.trim().toLowerCase();
			if (arg === "" || arg === "toggle") {
				await setEnabled(ctx, !enabled);
				return;
			}
			if (arg === "on" || arg === "off") {
				await setEnabled(ctx, arg === "on");
				return;
			}
			if (arg === "status") {
				const now = Date.now();
				ctx.ui.notify(`token speed ${enabled ? "on" : "off"} · live ${fmtTps(windowTps(now))} t/s · avg ${fmtTps(averageTps(now))} t/s`, "info");
				return;
			}
			ctx.ui.notify("Usage: /speed [toggle|on|off|status]", "warning");
		},
	});

	pi.on("session_start", async (_event, ctx) => {
		lastCtx = ctx;
		reset();

		const section = (pi.getSettings() as Record<string, unknown>)[SETTINGS_SECTION];
		if (section && typeof section === "object" && !Array.isArray(section)) {
			const value = (section as Record<string, unknown>).enabled;
			if (typeof value === "boolean") enabled = value;
		}

		// Resumed sessions keep the token total for the active branch.
		for (const entry of ctx.sessionManager.getBranch()) {
			if (entry.type !== "message" || entry.message.role !== "assistant") continue;
			stats.tokens += (entry.message as AssistantMessage).usage?.output ?? 0;
		}

		showStatus(ctx);
	});

	pi.on("model_select", async (_event, ctx) => {
		lastCtx = ctx;
		calib = 1; // tokenizers differ between models
		showStatus(ctx);
	});

	pi.on("message_start", async (event, ctx) => {
		lastCtx = ctx;
		if (event.message.role !== "assistant") return;
		msg = { firstDeltaMs: 0, lastDeltaMs: 0, estimated: 0, reported: 0, total: 0 };
	});

	// Hot path: runs in stream order, so keep it allocation-light and render throttled.
	pi.on("message_update", async (event, ctx) => {
		if (!enabled || !msg) return;
		lastCtx = ctx;
		const streamEvent = event.assistantMessageEvent;
		if (streamEvent.type !== "text_delta" && streamEvent.type !== "thinking_delta" && streamEvent.type !== "toolcall_delta") return;

		const now = Date.now();
		if (!msg.firstDeltaMs) msg.firstDeltaMs = now;
		msg.lastDeltaMs = now;

		const estimated = estimateTokens(streamEvent.delta);
		if (estimated > 0) {
			msg.estimated += estimated;
			bumpMessage(msg.estimated * calib, now);
		}
		refresh();
	});

	// Raw provider events carry usage that normalized events do not.
	pi.on("provider_stream_event", async (event, ctx) => {
		if (!enabled || !msg) return;
		lastCtx = ctx;
		const reported = extractOutputTokens(event.data);
		if (!reported || reported <= msg.reported) return;
		msg.reported = reported;
		bumpMessage(Math.max(msg.estimated * calib, reported), Date.now());
	});

	pi.on("message_end", async (event, ctx) => {
		lastCtx = ctx;
		if (!msg || event.message.role !== "assistant") return;
		const now = Date.now();
		const usage = (event.message as AssistantMessage).usage;
		if (usage && typeof usage.output === "number" && usage.output > 0) {
			msg.reported = Math.max(msg.reported, usage.output);
			const correction = usage.output - msg.total;
			if (correction !== 0) {
				stats.tokens += correction;
				msg.total = usage.output;
			}
			if (msg.estimated > 0) calib = clamp(0.8 * calib + 0.2 * (usage.output / msg.estimated), 0.5, 2);
		}
		if (msg.firstDeltaMs) stats.genMs += Math.max(0, (msg.lastDeltaMs || now) - msg.firstDeltaMs);
		msg = undefined;
		refresh(true);
	});

	// Idempotent cleanup: reload, session replacement, and exit can converge here.
	pi.on("session_shutdown", async (_event, ctx) => {
		if (ctx.hasUI) ctx.ui.setStatus(STATUS_KEY, undefined);
		lastCtx = undefined;
		reset();
	});
}
