# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.


- `Run.formatter_inputs/1` evaluates the host's `.formatter.exs` in menard's VM, whose cwd is
  menard's (or the session's first directory): a `.formatter.exs` that computes its inputs with a
  relative `Path.wildcard` globs the wrong tree, and `run format` with no files formats too little.
  The cwd is the whole VM's, so a `File.cd!` around the eval is not safe in the server; the inputs
  want asking of the host's formatter process (`priv/format.exs`), which runs in the host.

From the review before 0.8.10 went to Hex, reproduced and not fixed:

- `rename Mod.fun` and `find calls Mod.fun` read a file's aliases as one map for the whole file
  (`Find.collect_aliases`): in a file of two modules where each aliases a different `A`, the other
  module's `A.fun` is taken for the target's.
- `rename Old New` (a module) leaves the `Elixir.Old` spelling and `:"Elixir.Old"`.
- `clause move`/`split` leave behind a local `@type` that the moved `@spec` uses, and answer
  `unresolved: []`: the target does not compile.
- `run test`: a test that fails, then passes on the rerun, answers `ok: true` (`flaky` names it);
  and the rerun is skipped when any other failure (a warning) is in the reply. A warning's `message`
  is its first line only, so a type warning reads "comparison between distinct types found:".
- `Menard.Format.Worker`: its staleness fingerprint misses a path dependency's formatter plugin
  rebuilt, and its `GenServer.call(…, :infinity)` waits for ever on a wedged host VM.
- `Run.refusal/1` can put an unrelated `** (` line of the log in the place of a timeout's note.
- `deps add` that fails leaves the `mix.lock` it made.
- The LSP client (`Menard.Lsp`): file URIs not percent-encoded, columns counted in graphemes where
  the protocol counts UTF-16 units, no `didOpen`.
- Hooks: the read dedupe is keyed by session, so a subagent's Read of a file its parent read is
  told "already read" (unverified against a live subagent); the door's key is the session id, lost
  after `/clear` (unverified); `Hook.newer` walks the whole cwd after every Bash call, which is
  `~` for a session started there; a payload that is not a JSON object crashes the hook.
- `edit`: a write is not atomic (a kill mid-batch leaves some files written), `restore` leaves the
  directories `mkdir_p!` made, `replacements` counts edits and not occurrences under `all`.
- `outline`: a head with a default and a guard, `def one(a, b \\ 2) when is_integer(a)`, reads
  `(a, b when is_integer(a))`.
- Library mode: `mix menard.VERB --help` is a usage error (only `mix menard.help VERB` answers).
- `mix.exs` says `~> 1.18` and no run of the package on 1.18 has been made.
