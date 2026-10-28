import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import test from "node:test";
import type { ExtensionCommandContext, SessionProjection } from "@earendil-works/pi-coding-agent";
import { buildRescuePlan, createRecoveryCopy, createRescueHandler, excerpt, MAX_SUMMARY_CHARS } from "../rescue.ts";

const usage = { input: 100, output: 20, cacheRead: 0, cacheWrite: 0, totalTokens: 120,
	cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } };
const user = (text: string) => ({ role: "user", content: [{ type: "text", text }], timestamp: 1 });
const assistant = (text: string, stopReason = "stop") => ({ role: "assistant", content: [{ type: "text", text }],
	api: "openai-completions", provider: "test", model: "test-model", stopReason, timestamp: 2, usage });
const tool = (text: string) => ({ role: "toolResult", content: [{ type: "text", text }],
	toolCallId: "tool-1", toolName: "bash", isError: false, timestamp: 3 });
function projection(messages: unknown[]): SessionProjection {
	return { entries: messages.map((message, i) => ({ sourceEntry: { id: `entry-${i}` }, messages: [message] })),
		messages, model: { provider: "test", modelId: "test-model" }, thinkingLevel: "high" } as SessionProjection;
}
const options = { sourceFile: "/tmp/original.jsonl", cwd: "/tmp/project" };

test("discard corrupt latest turn but retain earlier goals, completed work, tool facts and all pending requests", () => {
	const p = buildRescuePlan(projection([
		user("只改导入边界，保留现有改动"),
		assistant("内部 UTF-8 已处理，下一步处理资源包"),
		user("外部资源包的问题你也解决好"),
		tool("已写入 tools/import.py；测试尚未执行"),
		assistant("文化建设<｜box｜>random multilingual garbage", "aborted"),
		user("继续，保持严格解码"),
		assistant("another corrupt reply that incorrectly reports success"),
	]), options);
	assert.match(p.summary, /只改导入边界/);
	assert.match(p.summary, /内部 UTF-8 已处理/);
	assert.match(p.summary, /tools\/import.py/);
	assert.doesNotMatch(p.summary, /multilingual garbage|another corrupt reply/);
	assert.deepEqual(p.pendingUsers.map((m) => m.content), [user("外部资源包的问题你也解决好").content, user("继续，保持严格解码").content]);
	assert.equal(p.lastGoodEntryId, "entry-1");
	assert.equal(p.excludedAssistantEntries, 2);
});

test("do not recycle even a stop-marked final response in the turn being rescued", () => {
	const p = buildRescuePlan(projection([user("修复 A"), assistant("garbled-success")]), options);
	assert.equal(p.lastGoodEntryId, undefined);
	assert.doesNotMatch(p.summary, /garbled-success/);
	assert.equal(p.pendingUsers.length, 1);
});

test("reasoning and unfinished tool calls cannot leak into the handoff", () => {
	const prior = assistant("可见的上次结论");
	prior.content.push({ type: "thinking", thinking: "PRIVATE_REASONING" } as never);
	const p = buildRescuePlan(projection([user("旧目标"), prior, user("新目标"), {
		...assistant("", "toolUse"), content: [{ type: "toolCall", id: "orphan", name: "bash", arguments: { command: "DO_NOT_REPLAY" } }],
	}, assistant("BROKEN", "error")]), options);
	assert.match(p.summary, /可见的上次结论/);
	assert.doesNotMatch(p.summary, /PRIVATE_REASONING|DO_NOT_REPLAY|BROKEN/);
	assert.equal(p.pendingUsers[0].role, "user");
});

test("preserve pending image attachments byte-for-byte and without mutating the original message", () => {
	const pending = { ...user("检查图片"), content: [{ type: "text", text: "检查图片" }, { type: "image", data: "YWJjZA==", mimeType: "image/png" }] };
	const p = buildRescuePlan(projection([pending, assistant("broken", "aborted")]), options);
	assert.deepEqual(p.pendingUsers[0], pending);
	(p.pendingUsers[0].content as { text?: string }[])[0].text = "changed";
	assert.equal(pending.content[0].text, "检查图片");
});

test("bounded excerpts retain both ends, avoid surrogate damage, and carry the user's rescue notes", () => {
	const text = "START " + "😀中".repeat(50_000) + " IMPORTANT_END";
	const p = buildRescuePlan(projection([
		{ role: "compactionSummary", summary: text, timestamp: 0, tokensBefore: 50_000 },
		user(text), assistant(text), user("待办"), tool(text), assistant("bad", "error"),
	]), { ...options, notes: "只修复编码，不改协议" });
	assert.ok(p.summary.length <= MAX_SUMMARY_CHARS);
	assert.match(p.summary, /START/);
	assert.match(p.summary, /IMPORTANT_END/);
	assert.match(p.summary, /只修复编码，不改协议/);
	assert.ok(p.summary.isWellFormed());
	for (const limit of [0, 1, 2, 10, 100]) {
		const s = excerpt("😀".repeat(100), limit);
		assert.ok(s.length <= limit);
		assert.ok(s.isWellFormed());
	}
});

const sdkRoot = process.env.PI_RESCUE_TEST_PACKAGE;
const sdkTest = { skip: !sdkRoot && "set PI_RESCUE_TEST_PACKAGE to the installed pi package for SDK integration tests" };
async function fixture(t: { after(fn: () => void): void }) {
	const { SessionManager } = await import(pathToFileURL(join(sdkRoot!, "dist/core/session-manager.js")).href);
	const root = mkdtempSync(join(tmpdir(), "pi-rescue-test-"));
	t.after(() => rmSync(root, { recursive: true, force: true }));
	const source = SessionManager.create(root, root);
	source.appendModelChange("test", "test-model");
	source.appendThinkingLevelChange("high");
	source.appendMessage(user("保留文件，不要提交"));
	source.appendMessage(assistant("已修改 A，尚未修改 B"));
	source.appendMessage(user("继续修改 B"));
	source.appendMessage(tool("B 修改成功，未运行测试"));
	source.appendMessage(assistant("CORRUPTED_OUTPUT", "aborted"));
	return { SessionManager, root, source };
}
function hash(path: string) { return createHash("sha256").update(readFileSync(path)).digest("hex"); }
function snapshot(source: any, root: string) {
	return { sourceFile: source.getSessionFile(), sessionDir: root, cwd: root, leafId: source.getLeafId(),
		name: "工作", model: { provider: "test", id: "test-model" }, thinkingLevel: "high", tokensBefore: 150_000,
		plan: buildRescuePlan(source.buildSessionProjection(), { sourceFile: source.getSessionFile(), cwd: root }) };
}

test("real SDK fork preserves original bytes and history while reopening with compact clean context", sdkTest, async (t) => {
	const { SessionManager, root, source } = await fixture(t);
	const originalHash = hash(source.getSessionFile());
	const path = createRecoveryCopy(snapshot(source, root), (...args) => SessionManager.forkFrom(...args));
	const recovered = SessionManager.open(path);
	assert.equal(hash(source.getSessionFile()), originalHash);
	assert.notEqual(path, source.getSessionFile());
	assert.notEqual(recovered.getSessionId(), source.getSessionId());
	assert.equal(recovered.getHeader().parentSession, source.getSessionFile());
	assert.match(readFileSync(path, "utf8"), /CORRUPTED_OUTPUT/);
	const context = recovered.buildSessionContext();
	assert.doesNotMatch(JSON.stringify(context.messages), /CORRUPTED_OUTPUT/);
	assert.equal(context.messages.filter((m: any) => m.role === "user").length, 1);
	assert.match(JSON.stringify(context.messages), /继续修改 B/);
	assert.deepEqual(context.model, { provider: "test", modelId: "test-model" });
	assert.equal(context.thinkingLevel, "high");
	assert.equal(statSync(path).mode & 0o777, 0o600);
	assert.ok(!readdirSync(root).some((name) => name.startsWith(".rescue-")));
});

test("current branch and context edits win over later abandoned branches on disk", sdkTest, async (t) => {
	const { SessionManager, root, source } = await fixture(t);
	const activeLeaf = source.getLeafId();
	const editTarget = source.getBranch().find((e: any) => e.message?.role === "user");
	source.appendContextEdit(editTarget.id, { content: [{ type: "text", text: "EDITED_REQUIREMENT" }] });
	const editedLeaf = source.getLeafId();
	source.branch(activeLeaf);
	source.appendMessage(user("ABANDONED_BRANCH_SECRET"));
	source.appendMessage(assistant("UNRELATED_BRANCH_RESULT"));
	source.branch(editedLeaf);
	const path = createRecoveryCopy(snapshot(source, root), (...args) => SessionManager.forkFrom(...args));
	const context = JSON.stringify(SessionManager.open(path).buildSessionContext().messages);
	assert.match(context, /EDITED_REQUIREMENT/);
	assert.doesNotMatch(context, /ABANDONED_BRANCH_SECRET|UNRELATED_BRANCH_RESULT|保留文件，不要提交/);
	assert.match(readFileSync(path, "utf8"), /ABANDONED_BRANCH_SECRET/);
});

test("failed private staging leaves no partial recovery and never changes the original", sdkTest, async (t) => {
	const { root, source } = await fixture(t);
	const before = readdirSync(root).sort();
	const originalHash = hash(source.getSessionFile());
	assert.throws(() => createRecoveryCopy(snapshot(source, root), () => { throw new Error("simulated disk failure"); }), /simulated disk failure/);
	assert.deepEqual(readdirSync(root).sort(), before);
	assert.equal(hash(source.getSessionFile()), originalHash);
});

function commandContext(source: any, root: string, mode: "success" | "cancel" | "throw" = "success") {
	const notices: string[] = [];
	let stale = false;
	let editor = "未发送的草稿";
	let switchedPath: string | undefined;
	const fresh = { ui: { setEditorText(value: string) { editor = value; }, notify(value: string) { notices.push(value); } } };
	const check = () => assert.equal(stale, false, "old command ctx accessed after session switch");
	const ctx = {
		cwd: root, sessionManager: source, model: { provider: "test", id: "test-model" }, thinkingLevel: "high",
		isIdle() { check(); return true; }, hasPendingMessages() { check(); return false; },
		getContextUsage() { check(); return { tokens: 150_000 }; },
		ui: { getEditorText() { check(); return editor; }, notify(value: string) { check(); notices.push(value); } },
		async switchSession(path: string, options: any) {
			switchedPath = path;
			if (mode === "cancel") return { cancelled: true };
			if (mode === "throw") throw new Error("switch failed");
			stale = true;
			await options.withSession(fresh);
			return { cancelled: false };
		},
	} as unknown as ExtensionCommandContext;
	return { ctx, notices, editor: () => editor, path: () => switchedPath };
}

test("command switches using fresh context, preserves draft, and makes zero model calls", sdkTest, async (t) => {
	const { SessionManager, root, source } = await fixture(t);
	const state = commandContext(source, root);
	Object.defineProperty(state.ctx, "modelRegistry", { get() { throw new Error("rescue must not request a model"); } });
	await createRescueHandler((...args) => SessionManager.forkFrom(...args))("先验证 B", state.ctx);
	assert.ok(state.path() && existsSync(state.path()!));
	assert.equal(state.editor(), "未发送的草稿");
	assert.match(state.notices.join("\n"), /Switched to the recovery copy/);
	assert.match(JSON.stringify(SessionManager.open(state.path()).buildSessionContext()), /先验证 B/);
});

for (const mode of ["cancel", "throw"] as const) {
	test(`switch ${mode} retains a usable recovery path`, sdkTest, async (t) => {
		const { SessionManager, root, source } = await fixture(t);
		const state = commandContext(source, root, mode);
		await createRescueHandler((...args) => SessionManager.forkFrom(...args))( "", state.ctx);
		assert.ok(existsSync(state.path()!));
		assert.match(state.notices.join("\n"), /pi --session/);
		assert.equal(SessionManager.open(state.path()).buildSessionContext().messages.filter((m: any) => m.role === "user").length, 1);
	});
}

test("busy command aborts and waits before reading the finalized session", sdkTest, async (t) => {
	const { SessionManager, root, source } = await fixture(t);
	const state = commandContext(source, root);
	let settled = false;
	let aborted = false;
	state.ctx.isIdle = () => settled;
	state.ctx.abort = () => { aborted = true; };
	state.ctx.waitForIdle = async () => { assert.equal(aborted, true); settled = true; };
	await createRescueHandler((...args) => { assert.equal(settled, true); return SessionManager.forkFrom(...args); })("", state.ctx);
	assert.ok(state.path());
});

test("queued input is never discarded by switching sessions", sdkTest, async (t) => {
	const { root, source } = await fixture(t);
	const state = commandContext(source, root);
	state.ctx.hasPendingMessages = () => true;
	const before = readdirSync(root).sort();
	await createRescueHandler(() => { throw new Error("must not fork queued input"); })("", state.ctx);
	assert.deepEqual(readdirSync(root).sort(), before);
	assert.match(state.notices.join("\n"), /queued messages/);
});
