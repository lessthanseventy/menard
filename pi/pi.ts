// The slice of pi's ExtensionAPI that menard's adapter depends on — hand-declared, minimal,
// type-only (erased at runtime). menard uses two hooks: `tool_call` (the guard, before a tool
// runs) and `tool_result` (format-on-save, after). See pi docs/extensions.md §tool_call /
// §tool_result.
//
// Hand-declared against pi's documented surface (github.com/earendil-works/pi, the
// @earendil-works/pi-coding-agent package), deliberately minimal: it names exactly the hooks and
// the one ctx field this adapter needs. When pi publishes its own types, this is what to replace.

export interface ExtensionContext {
  cwd: string;
}

// edit/write carry `path`; bash and the rest don't, and the guard is only about files.
export interface ToolCallEvent {
  toolName: string;
  toolCallId: string;
  input: { path?: string } & Record<string, unknown>;
}

export interface ToolCallEventResult {
  /** Block tool execution. The reason reaches the model as the tool's error. */
  block?: boolean;
  reason?: string;
}

export interface ToolResultEvent {
  toolName: string;
  toolCallId: string;
  input: { path?: string } & Record<string, unknown>;
  isError?: boolean;
}

export interface ToolResultPatch {
  content?: unknown;
  isError?: boolean;
}

export interface ExtensionAPI {
  on(
    event: "tool_call",
    handler: (
      event: ToolCallEvent,
      ctx: ExtensionContext,
    ) => ToolCallEventResult | undefined | Promise<ToolCallEventResult | undefined>,
  ): void;
  on(
    event: "tool_result",
    handler: (
      event: ToolResultEvent,
      ctx: ExtensionContext,
    ) => ToolResultPatch | undefined | Promise<ToolResultPatch | undefined>,
  ): void;
}