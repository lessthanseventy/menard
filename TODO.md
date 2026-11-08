# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- The gate is 420 s at load 10 (was 554 s; the identity corpus split into eight modules, bin_test
  async). What is left is subprocess work that parallelism already covers and a loaded box
  stretches: RunTest's 50 real mix runs (169 s serial), BinCopyTest's five cold compiles of a copied
  checkout (100 s serial), and ~100 formatter VM boots for scratch projects (2 s each). The next
  cuts are structural: one built copy per BinCopyTest module (`setup_all`) that each test `cp -a`s
  and breaks, and one compiled host project RunTest's green runs share.
