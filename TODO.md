# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.


- `Run.formatter_inputs/1` evaluates the host's `.formatter.exs` in menard's VM, whose cwd is
  menard's (or the session's first directory): a `.formatter.exs` that computes its inputs with a
  relative `Path.wildcard` globs the wrong tree, and `run format` with no files formats too little.
  The cwd is the whole VM's, so a `File.cd!` around the eval is not safe in the server; the inputs
  want asking of the host's formatter process (`priv/format.exs`), which runs in the host.
