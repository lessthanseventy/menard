# TODO

Found and not yet fixed. Fix it, or write it here, never just "noted". Delete a line when its
commit lands.

- `eval/run.py` builds its arms from the two-plugin layout (`manos/`, command hooks in
  `hooks/hooks.json`), gone since the plugins merged and the hooks became `mcp_tool` calls:
  `build_plugins` fails on every arm but A, and `eval/tests/test_arms.py` errors (1 of 60). The
  two-arm runner (with / without) replaces it; until then no round can be started.
