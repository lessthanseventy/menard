#!/usr/bin/env bash
# Per run: KEY=VALUE lines the agent and its check run under. Everything live is out of reach:
# throwaway databases, a dead service URL, an MCP port and a release node/cookie of the run's own,
# and systemctl/journalctl stubs first on PATH. The toolchain is Tlön's, through mise.
# Args: RID WS
rid=$1 ws=$2
n=$(printf '%s' "$rid" | cksum | cut -d' ' -f1)
tag=$(printf '%s' "$rid" | tr -c 'a-zA-Z0-9' '_' | tr 'A-Z' 'a-z' | cut -c1-40)
here=$(cd "$(dirname "$0")" && pwd)
trusted=$(dirname "$(dirname "$ws")")
path=$(MISE_TRUSTED_CONFIG_PATHS="$trusted" mise env -C "$ws" --json | jq -r '.PATH')
echo "PATH=$here/stubs:$path"
echo "MISE_TRUSTED_CONFIG_PATHS=$trusted"
echo "TLON_DATABASE=evd_$tag"
echo "TLON_TEST_DATABASE=evt_$tag"
echo "TLON_MCP_PORT=$((45000 + n % 5000))"
echo "TLON_MCP_URL=http://127.0.0.1:9/mcp"
echo "RELEASE_NODE=eval_$tag"
echo "RELEASE_COOKIE=eval_$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"
echo "TLON_DATABASE_URL="
# tmux of the run's own: Tlön's tests start tmux servers, and its sandbox keeps /tmp (the default
# socket dir) read-only, so they failed inside every agent's session. ~/.cache is writable in that
# sandbox; the operator's own server (the live cockpit's, in /tmp) stays out of reach. Not in the
# workspace: its snapshot for each step's check is a cp -a, and a live socket is no file to copy.
# Short: a socket path has ~108 bytes.
# tmux makes tmux-UID inside it, not the directory itself
mkdir -p "$HOME/.cache/mt/$n"
echo "TMUX_TMPDIR=$HOME/.cache/mt/$n"
