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
//
// See docs/adapters.md — the Claude Code plugin is one adapter; this is another.

import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
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
const MENARD = process.env.MENARD_BIN ?? join(dirname(import.meta.dir), "bin", "menard");

export default function menard(pi: ExtensionAPI): void {
  pi.on("tool_call", (event, ctx) => guard(event, ctx));
  pi.on("tool_result", (event, ctx) => formatTouched(event, ctx));
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
    const { status, stderr } = await run(MENARD, ["guard", file], ctx.cwd);
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

// -- spawn helpers ---------------------------------------------------------------------------

function run(
  cmd: string,
  args: string[],
  cwd: string,
): Promise<{ status: number | null; stdout: string; stderr: string }> {
  return new Promise((resolve, reject) => {
    const proc = spawn(cmd, args, { cwd, stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    proc.stdout?.on("data", (d: Buffer | string) => (stdout += d));
    proc.stderr?.on("data", (d: Buffer | string) => (stderr += d));
    proc.on("close", (status) => resolve({ status, stdout, stderr }));
    proc.on("error", reject);
  });
}

function runQuiet(cmd: string, args: string[], cwd: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const proc = spawn(cmd, args, { cwd, stdio: "ignore" });
    proc.on("close", () => resolve());
    proc.on("error", reject);
  });
}