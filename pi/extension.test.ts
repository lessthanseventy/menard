import { describe, expect, test } from "bun:test";
import { elixirFile } from "./extension.ts";

// elixirFile is the pure decision both hooks share — test it without spawning menard.
// The guard and format-on-save only act on an edit/write of an .ex/.exs; everything else
// (bash, read, .ts, a missing path) is left alone.

describe("elixirFile — which edits the guard and formatter act on", () => {
  test("an .ex edit → the file path", () => {
    expect(elixirFile("edit", { path: "/home/andrew/projects/ficciones/modules/server/lib/server/mcp/gateway.ex" })).toBe(
      "/home/andrew/projects/ficciones/modules/server/lib/server/mcp/gateway.ex",
    );
  });

  test("an .exs write → the file path", () => {
    expect(elixirFile("write", { path: "/home/andrew/projects/ficciones/modules/console/config/runtime.exs" })).toBe(
      "/home/andrew/projects/ficciones/modules/console/config/runtime.exs",
    );
  });

  test("a .ts edit is left alone (not Elixir)", () => {
    expect(elixirFile("edit", { path: "/home/andrew/projects/menard/pi/extension.ts" })).toBeNull();
  });

  test("a non-edit/write tool is left alone", () => {
    expect(elixirFile("bash", { path: "/x.ex" })).toBeNull();
    expect(elixirFile("read", { path: "/x.ex" })).toBeNull();
  });

  test("an edit with no path is left alone", () => {
    expect(elixirFile("edit", {})).toBeNull();
    expect(elixirFile("edit", null)).toBeNull();
    expect(elixirFile("edit", undefined)).toBeNull();
  });

  test("a non-Elixir file is left alone", () => {
    expect(elixirFile("edit", { path: "/home/andrew/projects/menard/.tool-versions" })).toBeNull();
    expect(elixirFile("edit", { path: "/home/andrew/projects/menard/README.md" })).toBeNull();
  });

  // mix.exs IS an .exs file — elixirFile returns it; the guard verb itself exempts it
  // (config/*.exs, .formatter.exs, mix.lock — the decision is menard's, not this extension's).
  test("mix.exs passes through to the guard (it is an .exs)", () => {
    expect(elixirFile("edit", { path: "/home/andrew/projects/menard/mix.exs" })).toBe(
      "/home/andrew/projects/menard/mix.exs",
    );
  });
});