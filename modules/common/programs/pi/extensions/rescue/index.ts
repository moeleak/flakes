/**
 * /rescue [additional notes]
 *
 * Fork the current session, replace its active context with bounded local
 * excerpts, and switch to the recovery copy. No model request is needed.
 * Run /reload after installing or editing this extension.
 */
import { SessionManager, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { createRescueHandler } from "./rescue.ts";

export default function rescue(pi: ExtensionAPI): void {
	pi.registerCommand("rescue", {
		description: "Recover a broken session: preserve full history and create a recovery branch from local excerpts (optional notes)",
		handler: createRescueHandler((...args) => SessionManager.forkFrom(...args)),
	});
}
