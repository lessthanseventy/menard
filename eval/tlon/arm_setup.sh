#!/usr/bin/env bash
# Tlön as each arm would find it. Its AGENTS.md sends Elixir tests and the gate through menard
# (`mise run menard -- run …`): an arm with menard gets that door working, on its own pinned copy;
# arm A, Tlön without menard, gets the notes as they read before that paragraph, and the door stays
# a stub that refuses. Args: ARM PLUGIN_DIR; runs in the workspace.
set -euo pipefail
arm=$1 plugin=$2
if [[ "$arm" == A ]]; then
  python3 - <<'PY'
p = "AGENTS.md"; s = open(p).read()
a = s.find("**Elixir tests and the gate go through Menard")
if a >= 0:
    b = s.index("\n\n", a)
    s = s[:a].rstrip("\n") + s[b:]
    open(p, "w").write(s)
PY
else
  printf '#!/usr/bin/env bash\nexport MENARD_CWD="${MISE_ORIGINAL_CWD:-$PWD}"\nexec %q "$@"\n' "$plugin/bin/menard" > scripts/menard.sh
fi
