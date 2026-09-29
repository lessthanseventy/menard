#!/usr/bin/env bash
# Tlön as each arm would find it. Its AGENTS.md sends Elixir tests and the gate through menard
# (`mise run menard -- run …`): an arm with menard gets that door working, on its own pinned copy;
# the arm without gets the notes as they read before that paragraph, and the door stays
# a stub that refuses. Args: ARM PLUGIN_DIR; runs in the workspace.
set -euo pipefail
arm=$1 plugin=$2
if [[ "$arm" == without ]]; then
  python3 - <<'PY'
p = "AGENTS.md"; s = open(p).read()
a = s.find("**Elixir tests and the gate go through Menard")
if a >= 0:
    b = s.index("\n\n", a)
    s = s[:a].rstrip("\n") + s[b:]
    open(p, "w").write(s)
PY
else
  # the door build.sh kept aside (hide_menard.py): the task file, its include, and the CLI script,
  # on this arm's own pinned menard
  door="$(dirname "$(dirname "$plugin")")/menard-door"
  cp "$door/menard.toml" tasks/menard.toml
  sed -i 's|"tasks/pi.toml"\]|"tasks/pi.toml", "tasks/menard.toml"]|' mise.toml
  grep -q '"tasks/menard.toml"' mise.toml || { echo "arm_setup: could not restore the menard task include" >&2; exit 1; }
  printf '#!/usr/bin/env bash\nexport MENARD_CWD="${MISE_ORIGINAL_CWD:-$PWD}"\nexec %q "$@"\n' "$plugin/bin/menard" > scripts/menard.sh
  chmod +x scripts/menard.sh
fi
