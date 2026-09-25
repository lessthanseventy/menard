// The Claude Code hook scripts that only advise, run for pi: hooks/shell-edits.sh (a module a bash
// command changed) and hooks/read-hint.sh (a big module read whole), fed Claude Code's payload
// shape. A file of its own because pi's loader inlines each file as a data: URL: extension.ts at 7 KB
// failed to load (NameTooLong) where 4.5 KB loaded.

import { dirname, join, resolve as resolvePath } from "node:path";
import { fileURLToPath } from "node:url";
import { run } from "./spawn.ts";
import type { ExtensionContext, ToolCallEvent, ToolResultEvent, ToolResultPatch } from "./pi.ts";

const HOOKS = join(dirname(dirname(fileURLToPath(import.meta.url))), "hooks"); // .url: see extension.ts
// the shell-edits mark is per session; one pi process is one session
const SESSION = `pi-${process.pid}`;

// Claude Code's tool names and input fields, which the scripts read
function hookInput(event: ToolCallEvent | ToolResultEvent, ctx: ExtensionContext) {
  const input = event.input as Record<string, unknown>;
  if (event.toolName === "bash") return { tool_name: "Bash", tool_input: { command: input.command } };
  if (event.toolName === "read" && typeof input.path === "string") {
    const file_path = resolvePath(ctx.cwd, input.path);
    return { tool_name: "Read", tool_input: { file_path, offset: input.offset, limit: input.limit } };
  }
  return null;
}

export async function hook(
  script: string,
  hook_event_name: string,
  event: ToolCallEvent | ToolResultEvent,
  ctx: ExtensionContext,
): Promise<string | null> {
  const shaped = hookInput(event, ctx);
  if (!shaped) return null;
  const payload = JSON.stringify({ hook_event_name, session_id: SESSION, cwd: ctx.cwd, ...shaped });
  try {
    const { status, stderr } = await run("bash", [join(HOOKS, script)], ctx.cwd, payload, {
      MENARD_TOOL_PREFIX: "menard__",
    });
    return status === 2 ? stderr.trim() : null;
  } catch {
    return null; // advice is best-effort
  }
}

export async function advise(event: ToolResultEvent, ctx: ExtensionContext): Promise<ToolResultPatch | undefined> {
  const script = { bash: "shell-edits.sh", read: "read-hint.sh" }[event.toolName];
  if (!script) return undefined;
  const note = await hook(script, "PostToolUse", event, ctx);
  if (!note) return undefined;
  return { content: [...(event.content ?? []), { type: "text", text: note }] };
}
