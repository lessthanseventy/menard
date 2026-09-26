# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- A verb whose build another process changes between bin/menard's own compile and the verb's mix
  answers with mix's compile log: with the dev build deleted and rebuilt beside it (2026-09-26, a
  scratch script racing a gate), `bin/menard attr get F limit` printed "Generated menard app" on
  STDOUT, where the answer (`5`) belongs; and a verb waiting on another's compile printed "Waiting
  for lock on the build directory (held by process N)" on stderr, which is neither a refusal nor
  an error. The verb's own mix could run with the compile already done (`--no-compile`) or its
  compile output kept off stdout.
