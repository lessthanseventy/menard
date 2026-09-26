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
- eval/tlon/cases/focus3's planted bug (setup.sh: the fuzzy filter's `score > 0` floor) is caught by
  Tlön's own suite: console/test/console/picker_test.exs:82 ("the palette's corpus finds a verb by
  what it DOES") goes red with the plant and green without (checked 2026-09-26 on the hidden-menard
  template). setup.sh says the plant slips past Tlön's tests; it does not, so both arms start on a
  red test that points at the fault, and step 1 is no misdirection. Re-plant so the project's own
  suite stays green and only the hidden tests catch it, then re-validate the step 1 grader.
