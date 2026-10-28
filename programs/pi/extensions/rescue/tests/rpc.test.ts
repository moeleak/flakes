/** Actual Pi process: extension discovery, command dispatch and session replacement. */
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

test("Pi auto-discovers /rescue and switches a real session without contacting any model", { timeout: 30_000 }, async () => {
	const root = mkdtempSync(join(tmpdir(), "pi-rescue-rpc-"));
	const agentDir = join(root, "agent");
	const extensions = join(agentDir, "extensions");
	mkdirSync(extensions, { recursive: true, mode: 0o700 });
	symlinkSync(fileURLToPath(new URL("../", import.meta.url)), join(extensions, "rescue"));
	const settings = { defaultProvider: "test", defaultModel: "fixture-model", quietStartup: true };
	writeFileSync(join(agentDir, "settings.json"), JSON.stringify(settings));
	writeFileSync(join(agentDir, "models.json"), JSON.stringify({ providers: { test: {
		baseUrl: "http://127.0.0.1:9/v1", api: "openai-completions", apiKey: "not-a-real-key",
		models: [{ id: "fixture-model", name: "Rescue offline test", reasoning: true,
			input: ["text"], contextWindow: 200_000, maxTokens: 4096 }],
	} } }));
	const usage = { input: 100, output: 10, cacheRead: 0, cacheWrite: 0, totalTokens: 110,
		cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } };
	const source = join(root, "source.jsonl");
	const sessionId = randomUUID();
	const messages = [
		{ role: "user", content: [{ type: "text", text: "保留工作区改动，统一 UTF-8" }], timestamp: 1 },
		{ role: "assistant", content: [{ type: "text", text: "内部数据已处理，外部资源仍待处理" }],
			api: "openai-completions", provider: "test", model: "fixture-model", stopReason: "stop", timestamp: 2, usage },
		{ role: "user", content: [{ type: "text", text: "外部资源包的问题你也解决好" }], timestamp: 3 },
		{ role: "assistant", content: [{ type: "text", text: "BAD_OUTPUT<｜box｜>random fragments" }],
			api: "openai-completions", provider: "test", model: "fixture-model", stopReason: "aborted", timestamp: 4, usage },
	];
	const timestamp = new Date().toISOString();
	writeFileSync(source, [
		{ type: "session", version: 3, id: sessionId, timestamp, cwd: root },
		{ type: "model_change", id: "model", parentId: null, timestamp, provider: "test", modelId: "fixture-model" },
		...messages.map((message, i) => ({ type: "message", id: `m${i}`, parentId: i ? `m${i - 1}` : "model", timestamp, message })),
	].map((entry) => JSON.stringify(entry)).join("\n") + "\n");
	const child = spawn("pi", ["--offline", "--mode", "rpc", "--session", source,
		"--no-mcp", "--no-skills", "--no-context-files", "--no-prompt-templates", "--no-tools"], {
		cwd: root, env: { ...process.env, PI_CODING_AGENT_DIR: agentDir }, stdio: ["pipe", "pipe", "pipe"],
	});
	const records: any[] = [];
	const pending = new Map<string, { resolve: (value: any) => void; reject: (error: Error) => void; timer: NodeJS.Timeout }>();
	let buffer = "";
	let stderr = "";
	child.stdout.setEncoding("utf8");
	child.stdout.on("data", (chunk: string) => {
		buffer += chunk;
		let end: number;
		while ((end = buffer.indexOf("\n")) >= 0) {
			const line = buffer.slice(0, end);
			buffer = buffer.slice(end + 1);
			if (!line.trim()) continue;
			let record: any;
			try { record = JSON.parse(line); } catch { continue; }
			records.push(record);
			const request = record.type === "response" ? pending.get(record.id) : undefined;
			if (request) {
				pending.delete(record.id);
				clearTimeout(request.timer);
				if (record.success) request.resolve(record.data);
				else request.reject(new Error(JSON.stringify(record)));
			}
		}
	});
	child.stderr.setEncoding("utf8");
	child.stderr.on("data", (chunk: string) => { stderr += chunk; });
	const failPending = (error: Error) => {
		for (const request of pending.values()) { clearTimeout(request.timer); request.reject(error); }
		pending.clear();
	};
	child.on("error", failPending);
	child.on("exit", () => failPending(new Error(`Pi exited unexpectedly: ${stderr}`)));
	let counter = 0;
	const command = (type: string, extra: Record<string, unknown> = {}) => new Promise<any>((resolve, reject) => {
		const id = `test-${++counter}`;
		const timer = setTimeout(() => { pending.delete(id); reject(new Error(`Timeout waiting for ${type}: ${stderr}`)); }, 10_000);
		pending.set(id, { resolve, reject, timer });
		child.stdin.write(JSON.stringify({ id, type, ...extra }) + "\n");
	});
	try {
		const commands = await command("get_commands");
		assert.ok(commands.commands.some((c: any) => c.name === "rescue"));
		const initial = await command("get_state");
		// Pi may persist its initial thinking/model selection during startup.
		// Measure preservation from the initialized session, before /rescue.
		const before = createHash("sha256").update(readFileSync(source)).digest("hex");
		const result = await command("prompt", { message: "/rescue 继续处理资源包，保留现有改动" });
		assert.equal(result.disposition, "handled");
		const current = await command("get_state");
		const context = await command("get_messages");
		assert.notEqual(current.sessionId, initial.sessionId);
		assert.equal(current.model.id, initial.model.id);
		assert.match(JSON.stringify(context.messages), /外部资源包的问题你也解决好/);
		assert.doesNotMatch(JSON.stringify(context.messages), /BAD_OUTPUT|random fragments/);
		assert.equal(createHash("sha256").update(readFileSync(source)).digest("hex"), before);
		assert.deepEqual(records.filter((r) => ["extension_error", "agent_start", "tool_execution_start"].includes(r.type)), []);
		assert.ok(records.some((r) => r.type === "extension_ui_request" && r.method === "set_editor_text"));
		assert.equal(stderr, "");
	} finally {
		const exited = new Promise<void>((resolve) => {
			if (child.exitCode !== null) resolve();
			else child.once("exit", () => resolve());
		});
		child.kill("SIGTERM");
		const kill = setTimeout(() => child.kill("SIGKILL"), 2000);
		await exited;
		clearTimeout(kill);
		rmSync(root, { recursive: true, force: true });
	}
});
