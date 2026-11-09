// crew status extension for Pi (Gentle Shell), loaded by crew with -e.
// Each Pi event runs crew's hook helper (scripts/hook.lua) detached, with the
// hook JSON on stdin, exactly like Claude's hooks:
//
//   agent_start      -> UserPromptSubmit (work)
//   ui_prompt_start  -> Notification     (ask), notification_type = prompt kind
//   ui_prompt_end    -> PostToolUse      (work)
//   (both ui_prompt events only during a turn; idle screens are ignored)
//   agent_settled    -> Stop             (done)
//   session_start    -> SessionStart     (only moves the session id)
//
// Outside a crew agent ($NVIM or $CREW_ID unset) it does nothing, and any
// failure is swallowed: status reporting must never get in Pi's way.
import { spawn } from "node:child_process";

function sessionId(ctx) {
	try {
		const id = ctx?.sessionManager?.getSessionId?.();
		return typeof id === "string" && id !== "" ? id : undefined;
	} catch {
		return undefined;
	}
}

function report(event, ctx, extra = {}) {
	const env = process.env;
	if (!env.NVIM || !env.CREW_ID || !env.CREW_HOOK_SCRIPT) return;
	try {
		const child = spawn(
			env.CREW_HOOK_NVIM || "nvim",
			["--clean", "--headless", "-l", env.CREW_HOOK_SCRIPT, event],
			{ detached: true, stdio: ["pipe", "ignore", "ignore"] },
		);
		child.on("error", () => {});
		child.stdin.on("error", () => {});
		child.stdin.end(JSON.stringify({ session_id: sessionId(ctx), ...extra }));
		child.unref();
	} catch {
		// never break Pi
	}
}

export default function (pi) {
	// ui_prompt_* also fires for screens the user opens while idle, such as
	// /gentle:profiles. Only a prompt inside a turn is the agent asking.
	let running = false;
	pi.on("agent_start", async (_event, ctx) => {
		running = true;
		report("UserPromptSubmit", ctx);
	});
	pi.on("ui_prompt_start", async (event, ctx) => {
		if (!running) return;
		report("Notification", ctx, { notification_type: typeof event?.kind === "string" ? event.kind : "ui_prompt" });
	});
	pi.on("ui_prompt_end", async (_event, ctx) => {
		if (running) report("PostToolUse", ctx);
	});
	pi.on("agent_settled", async (_event, ctx) => {
		running = false;
		report("Stop", ctx);
	});
	pi.on("session_start", async (_event, ctx) => report("SessionStart", ctx));
}
