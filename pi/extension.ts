// menard's pi adapter — the guard and format-on-save, as a pi extension menard ships from its
// own repo (the way it ships .claude-plugin/ for Claude Code). pi loads this file directly (no
// build step); it self-locates bin/menard relative to itself, so it works on any machine with a
// menard checkout and an Elixir toolchain, no host repo required.
//
//   tool_call    the guard: a raw edit/write on an .ex/.exs holding a defmodule is blocked —
//                use the verbs instead. `menard guard FILE` exits 2 with the reason; fail open
//                (never block) when menard is missing or errors.
//   tool_result  format-on-save: `menard run format FILE` on what was just written, so the file
//                on disk is always formatter-compliant. Best-effort and invisible.
//   advice       hooks/shell-edits.sh (a module a bash command changed) and hooks/read-hint.sh (a
//                big module read whole), the same scripts Claude Code runs, fed its payload shape;
//                what they say is appended to the tool's result. Never blocks.
//
// See docs/adapters.md — the Claude Code plugin is one adapter; this is another.

import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { advise, hook } from "./advice.ts";
import { run, runQuiet } from "./spawn.ts";
import type {
  ExtensionAPI,
  ToolCallEvent,
  ToolCallEventResult,
  ToolResultEvent,
  ToolResultPatch,
  ExtensionContext,
} from "./pi.ts";

// Self-locating: bin/menard is one level up from pi/extension.ts. MENARD_BIN overrides (a dev
// box pointing at a different checkout, or a Nix wrapper on PATH).
// import.meta.url, not import.meta.dir: pi loads an extension as a data: URL, and there .dir is that
// URL while .url is still the file's.
const MENARD = process.env.MENARD_BIN ?? join(dirname(dirname(fileURLToPath(import.meta.url))), "bin", "menard");

export default function menard(pi: ExtensionAPI): void {
  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName === "bash") await hook("shell-edits.sh", "PreToolUse", event, ctx);
    return guard(event, ctx);
  });
  pi.on("tool_result", (event, ctx) => formatTouched(event, ctx));
  pi.on("tool_result", (event, ctx) => advise(event, ctx));
}

// -- the shared decision: is this an edit/write on an .ex/.exs? -----------------------------

export function elixirFile(
  toolName: string,
  input: { path?: string } | null | undefined,
): string | null {
  if (toolName !== "edit" && toolName !== "write") return null;
  const file = input?.path;
  if (!file || !/\.(ex|exs)$/i.test(file)) return null;
  return file;
}

// -- guard -----------------------------------------------------------------------------------

async function guard(event: ToolCallEvent, ctx: ExtensionContext): Promise<ToolCallEventResult | undefined> {
  const file = elixirFile(event.toolName, event.input);
  if (!file) return undefined;
  // menard guard exits 2 with the reason on stderr when the file is a module; 0 for everything
  // else (new files, scripts with no module, config/, deps/, _build/). Fail open: a missing or
  // broken menard must never be the reason an edit is blocked.
  try {
    // --edit: the edit itself, so one that only changes text inside a string (a heredoc, a ~H
    // template, which no verb reaches into) can pass
    const edit = JSON.stringify(event.input ?? {});
    const { status, stderr } = await run(MENARD, ["guard", file, "--edit", edit], ctx.cwd);
    if (status === 2) return { block: true, reason: stderr.trim() };
  } catch {
    // menard not found or failed to start — fail open.
  }
  return undefined;
}

// -- format-on-save --------------------------------------------------------------------------

async function formatTouched(
  event: ToolResultEvent,
  ctx: ExtensionContext,
): Promise<ToolResultPatch | undefined> {
  const file = elixirFile(event.toolName, event.input);
  if (!file || event.isError) return undefined;
  // Best-effort and invisible: a format failure never fails the edit. The edit stands; the
  // formatted file is a silent side-effect. Never modify the result.
  try {
    await runQuiet(MENARD, ["run", "format", file], ctx.cwd);
  } catch {
    // silent — the edit stands regardless.
  }
  return undefined;
}
