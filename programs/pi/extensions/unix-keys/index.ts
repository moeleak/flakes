/**
 * Unix / readline-style navigation
 *
 * Bind ctrl+p and ctrl+n to the editor's prompt history and to up/down
 * movement in every selector list (model picker, session tree, dialogs, …),
 * like Emacs/readline. The rest of the readline editing keys (ctrl+a,
 * ctrl+e, ctrl+b, ctrl+f, ctrl+d, ctrl+k, ctrl+u, ctrl+w, ctrl+y) already
 * have working defaults.
 *
 * ctrl+p / ctrl+n normally cycle models. The editor and selector components
 * check these dedicated actions before app-level actions, so while the prompt
 * or a list is focused they navigate; model cycling stays available inside
 * the model selector.
 *
 * Usage: put this file in ~/.pi/agent/extensions/ and run /reload.
 */

import {
	CustomEditor,
	type ExtensionAPI,
	type KeybindingsManager,
} from "@earendil-works/pi-coding-agent";
import { Key, type KeyId } from "@earendil-works/pi-tui";

type NavigationBinding =
	| "tui.editor.historyPrevious"
	| "tui.editor.historyNext"
	| "tui.select.up"
	| "tui.select.down";

function asKeys(value: KeyId | KeyId[] | undefined): KeyId[] {
	if (value === undefined) return [];
	return Array.isArray(value) ? value : [value];
}

function addNavigationKeys(
	keybindings: KeybindingsManager,
	additions: Partial<Record<NavigationBinding, KeyId[]>>,
): void {
	const resolved = keybindings.getResolvedBindings();
	const user = keybindings.getUserBindings();
	const next = { ...user };

	for (const [action, newKeys] of Object.entries(additions) as [
		NavigationBinding,
		KeyId[],
	][]) {
		const keys = [...asKeys(next[action] ?? resolved[action])];
		for (const key of newKeys) {
			if (!keys.includes(key)) keys.push(key);
		}
		next[action] = keys;
	}

	keybindings.setUserBindings(next);
}

class UnixNavigationEditor extends CustomEditor {
	constructor(
		...args: ConstructorParameters<typeof CustomEditor>
	) {
		super(...args);
		addNavigationKeys(args[2], {
			"tui.editor.historyPrevious": [Key.ctrl("p")],
			"tui.editor.historyNext": [Key.ctrl("n")],
			"tui.select.up": [Key.ctrl("p")],
			"tui.select.down": [Key.ctrl("n")],
		});
	}
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		if (ctx.mode !== "tui") return;

		ctx.ui.setEditorComponent(
			(tui, theme, keybindings) => new UnixNavigationEditor(tui, theme, keybindings),
		);
	});

	pi.on("session_shutdown", (_event, ctx) => {
		if (ctx.mode === "tui") ctx.ui.setEditorComponent(undefined);
	});
}
