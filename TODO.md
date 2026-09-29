# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.


- `find calls` misses a call through `alias Mod, as: X` (`X.fun()`): `collect_aliases` reads only
  the last segment as the short name. Found 2026-09-29 on a bench beside expert, which finds it.
