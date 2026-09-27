# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- `clause move --delegate`: a delegate's default is the function's own text, evaluated in the
  source; one calling a function that moved (`x \\ helper()`) points at nothing there.
- `clause move`: an import without `only:` is copied when the moved code makes any call nothing
  defines, which a `use`-provided function also looks like; two such imports are both copied, and
  one the code does not use warns. An unused member of `alias A.{B, C}` is left in the source.
