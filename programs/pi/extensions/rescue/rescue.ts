import { chmodSync, linkSync, mkdtempSync, rmSync } from "node:fs";
import { basename, dirname, join } from "node:path";
import type { AgentMessage } from "@earendil-works/pi-agent-core";
import type { UserMessage } from "@earendil-works/pi-ai";
import type {
	ExtensionCommandContext,
	SessionManager,
	SessionProjection,
} from "@earendil-works/pi-coding-agent";

export const MAX_SUMMARY_CHARS = 16_000;
const CONTINUE_REQUEST = "Check the current files and task progress first, then continue the unfinished request above.";
const HELP = "/rescue [additional notes]\nKeep the original session history intact, create a recovery copy from local excerpts, and switch to it. No model call is needed; press Enter after recovery to continue. Excerpts may omit details, and the full record remains available in the original session.";

type ForkSession = typeof SessionManager.forkFrom;
type ProjectedMessage = { entryId: string; message: AgentMessage };

export interface RescuePlan {
	summary: string;
	pendingUsers: UserMessage[];
	lastGoodEntryId?: string;
	excludedAssistantEntries: number;
}

/** Bound excerpts while retaining both the beginning and the most recent tail. */
export function excerpt(text: string, limit: number): string {
	if (text.length <= limit) return text;
	const omitted = "\n...[middle omitted; see original session for full text]...\n";
	if (limit <= omitted.length) {
		const prefix = text.slice(0, Math.max(0, limit));
		return /[\uD800-\uDBFF]$/.test(prefix) ? prefix.slice(0, -1) : prefix;
	}
	const room = Math.max(0, limit - omitted.length);
	const head = Math.floor(room * 0.65);
	const tail = room - head;
	let left = text.slice(0, head);
	let right = tail ? text.slice(-tail) : "";
	// Never split a UTF-16 surrogate pair at an excerpt boundary.
	if (/[\uD800-\uDBFF]$/.test(left)) left = left.slice(0, -1);
	if (/^[\uDC00-\uDFFF]/.test(right)) right = right.slice(1);
	return left + omitted + right;
}

function visibleText(message: AgentMessage): string {
	if (!("content" in message)) return "";
	if (typeof message.content === "string") return message.content.trim();
	if (!Array.isArray(message.content)) return "";
	return message.content
		.filter((block): block is { type: "text"; text: string } => block.type === "text")
		.map((block) => block.text)
		.join("\n")
		.trim();
}

function userExcerpt(message: AgentMessage): string {
	const text = visibleText(message);
	if (!("content" in message) || !Array.isArray(message.content)) return text;
	const images = message.content.filter((block) => block.type === "image").length;
	return text + (images ? `\n[${images} image(s) attached; full attachments remain in the session]` : "");
}

/**
 * Only use the current projected branch, honoring previous compactions and
 * context edits. The most recent user turn is suspect even if its assistant
 * reply incorrectly reported a successful stop, so never use that reply as
 * the recovery handoff. Failed replies and reasoning are never summarized.
 */
export function buildRescuePlan(
	projection: SessionProjection,
	options: { sourceFile: string; cwd: string; notes?: string },
): RescuePlan {
	const rows: ProjectedMessage[] = projection.entries.flatMap(({ sourceEntry, messages }) =>
		messages.map((message) => ({ entryId: sourceEntry.id, message })),
	);
	let latestUser = -1;
	for (let i = rows.length - 1; i >= 0; i--) {
		if (rows[i].message.role === "user") {
			latestUser = i;
			break;
		}
	}

	let lastGood = -1;
	for (let i = (latestUser < 0 ? rows.length : latestUser) - 1; i >= 0; i--) {
		const message = rows[i].message;
		if (message.role === "assistant" && message.stopReason === "stop" && visibleText(message)) {
			lastGood = i;
			break;
		}
	}

	const pendingUsers = rows.slice(lastGood + 1)
		.map(({ message }) => message)
		.filter((message): message is UserMessage => message.role === "user");
	const excludedAssistantEntries = rows.slice(lastGood + 1)
		.filter(({ message }) => message.role === "assistant").length;

	const summaries = rows
		.filter(({ message }) => message.role === "compactionSummary" || message.role === "branchSummary")
		.slice(-2)
		.map(({ message }) => "summary" in message && typeof message.summary === "string" ? message.summary : "")
		.filter(Boolean);
	const earlierUsers = rows.slice(0, lastGood + 1).filter(({ message }) => message.role === "user");
	const requirements = earlierUsers.length > 5
		? [earlierUsers[0], ...earlierUsers.slice(-4)]
		: earlierUsers;
	const results = rows.slice(lastGood + 1)
		.filter(({ message }) => message.role === "toolResult")
		.slice(-3)
		.map(({ message }) => {
			if (message.role !== "toolResult") return "";
			return `[${message.toolName}${message.isError ? ", failed" : ", returned a result"}]\n${excerpt(visibleText(message), 650)}`;
		});

	const sections = [
		"This is a local recovery excerpt assembled by /rescue without a model-generated summary. It may omit details and is not re-verified fact.",
		`Working directory: ${options.cwd}\nFull original session (JSONL, consult as needed): ${options.sourceFile}`,
		"The full history remains in the recovery copy and the original session. This request uses this excerpt and the user requests retained below. The latest assistant output was removed from the active context; do not treat it as completed work.",
		"Before continuing, read any applicable AGENTS.md and verify the current files and actual progress. Tools from before the interruption may already have modified files or performed actions; check the results before deciding whether to retry, and preserve existing work.",
	];
	if (summaries.length) sections.push(`Earlier session summaries (excerpts):\n${excerpt(summaries.join("\n\n"), 3_000)}`);
	if (requirements.length) {
		sections.push("Earlier user requirements (verbatim excerpts, preserving usable goals and constraints):\n" + requirements
			.map(({ entryId, message }) => `[${entryId}] ${excerpt(userExcerpt(message), 650)}`)
			.join("\n\n"));
	}
	if (lastGood >= 0) {
		sections.push(`Assistant reply completed before the latest turn (excerpt; its conclusions and test claims are not yet re-verified):\n${excerpt(visibleText(rows[lastGood].message), 5_000)}`);
	} else {
		sections.push("No usable complete assistant reply was found before the latest turn. Recover task progress from the retained user requests, earlier summaries, and current files.");
	}
	if (results.length) sections.push(`Most recent tool results before the interruption (verbatim excerpts; do not assume the whole task is complete from these):\n${results.join("\n\n")}`);
	if (options.notes?.trim()) sections.push(`Additional requirements supplied when running /rescue:\n${excerpt(options.notes.trim(), 1_200)}`);
	sections.push(pendingUsers.length
		? `${pendingUsers.length} user request(s) and their original attachments are retained below. Verify which work is complete and continue the unfinished parts.`
		: "There are no user requests in the active context to reattach; consult the earlier summaries or ask the user for the next step.");

	return {
		summary: excerpt(sections.join("\n\n"), MAX_SUMMARY_CHARS),
		pendingUsers: structuredClone(pendingUsers),
		lastGoodEntryId: lastGood >= 0 ? rows[lastGood].entryId : undefined,
		excludedAssistantEntries,
	};
}

export interface RescueSnapshot {
	sourceFile: string;
	sessionDir: string;
	cwd: string;
	leafId: string;
	name?: string;
	model?: { provider: string; id: string };
	thinkingLevel?: string;
	tokensBefore: number;
	plan: RescuePlan;
}

/** Build privately, then publish the complete copy without overwriting a file. */
export function createRecoveryCopy(snapshot: RescueSnapshot, forkSession: ForkSession): string {
	const staging = mkdtempSync(join(snapshot.sessionDir, ".rescue-"));
	try {
		chmodSync(staging, 0o700);
		const copy = forkSession(snapshot.sourceFile, snapshot.cwd, staging);
		// A JSONL file may contain other branches after the active branch's leaf.
		copy.branch(snapshot.leafId);
		if (snapshot.model) copy.appendModelChange(snapshot.model.provider, snapshot.model.id);
		if (snapshot.thinkingLevel) copy.appendThinkingLevelChange(snapshot.thinkingLevel);
		copy.appendSessionInfo(`Recovered · ${excerpt(snapshot.name || basename(snapshot.cwd) || "session", 100)} · ${new Date().toISOString()}`);
		copy.appendCompaction(snapshot.plan.summary, null, snapshot.tokensBefore, {
			extension: "rescue",
			version: 1,
			sourceSession: snapshot.sourceFile,
			sourceLeafId: snapshot.leafId,
			lastGoodEntryId: snapshot.plan.lastGoodEntryId,
			excludedAssistantEntries: snapshot.plan.excludedAssistantEntries,
			summaryMethod: "local-excerpts",
		}, true);
		for (const message of snapshot.plan.pendingUsers) {
			copy.appendMessage({ ...message, timestamp: Date.now() });
		}
		const stagedFile = copy.getSessionFile();
		if (!stagedFile) throw new Error("Could not create a persistent recovery session.");
		chmodSync(stagedFile, 0o600);
		const destination = join(snapshot.sessionDir, basename(stagedFile));
		linkSync(stagedFile, destination);
		return destination;
	} finally {
		rmSync(staging, { recursive: true, force: true });
	}
}

export function createRescueHandler(forkSession: ForkSession) {
	let running = false;
	return async (args: string, ctx: ExtensionCommandContext): Promise<void> => {
		if (args.trim() === "help" || args.trim() === "--help") {
			ctx.ui.notify(HELP, "info");
			return;
		}
		if (running) {
			ctx.ui.notify("Recovering session, please wait.", "info");
			return;
		}
		running = true;
		let recoveryFile: string | undefined;
		let replacement: ExtensionCommandContext | undefined;
		try {
			if (!ctx.isIdle()) {
				ctx.ui.notify("Stopping the current request, then creating a recovery copy...", "info");
				ctx.abort();
				await ctx.waitForIdle();
			}
			if (ctx.hasPendingMessages()) {
				ctx.ui.notify("There are queued messages. Retrieve or handle them before running /rescue so nothing is lost during the switch.", "warning");
				return;
			}
			const sourceFile = ctx.sessionManager.getSessionFile();
			const leafId = ctx.sessionManager.getLeafId();
			if (!sourceFile || !leafId) {
				ctx.ui.notify("There is no saved conversation to recover.", "info");
				return;
			}
			const projection = ctx.sessionManager.buildSessionProjection();
			if (!projection.messages.some((message) => message.role === "user" || message.role === "compactionSummary" || message.role === "branchSummary")) {
				ctx.ui.notify("There are no user requests or work summaries to recover.", "info");
				return;
			}
			const editor = ctx.ui.getEditorText();
			const draft = editor.trim() && !/^\/rescue(?:\s|$)/.test(editor.trim()) ? editor : CONTINUE_REQUEST;
			const snapshot: RescueSnapshot = {
				sourceFile,
				sessionDir: ctx.sessionManager.getSessionDir() || dirname(sourceFile),
				cwd: ctx.cwd,
				leafId,
				name: ctx.sessionManager.getSessionName(),
				model: ctx.model ? { provider: ctx.model.provider, id: ctx.model.id } : undefined,
				thinkingLevel: ctx.thinkingLevel,
				tokensBefore: ctx.getContextUsage()?.tokens ?? 0,
				plan: buildRescuePlan(projection, { sourceFile, cwd: ctx.cwd, notes: args }),
			};
			recoveryFile = createRecoveryCopy(snapshot, forkSession);
			const switched = await ctx.switchSession(recoveryFile, {
				withSession: async (fresh) => {
					replacement = fresh;
					fresh.ui.setEditorText(draft);
					fresh.ui.notify("Switched to the recovery copy; the original session and full history are preserved. Press Enter to continue; run /rescue help for details.", "info");
				},
			});
			// The old ctx is only valid if replacement was cancelled.
			if (switched.cancelled) {
				ctx.ui.notify(`Recovery copy created, but the switch was cancelled. Run later: pi --session ${recoveryFile}`, "warning");
			}
		} catch (error) {
			const reason = error instanceof Error ? error.message : String(error);
			const message = recoveryFile
				? `Recovery copy saved: ${recoveryFile}\nSwitch did not complete: ${reason}\nRun: pi --session ${recoveryFile}`
				: `Recovery did not complete; the original session was not modified by this extension: ${reason}`;
			try {
				(replacement || ctx).ui.notify(message, "error");
			} catch {
				// If switching failed after invalidating the old ctx, let Pi's
				// command error handler surface the saved recovery path instead.
				throw new Error(message, { cause: error });
			}
		} finally {
			running = false;
		}
	};
}
