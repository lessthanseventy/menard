#!/usr/bin/env bash
# Per run: KEY=VALUE lines the agent and its check run under. The test database is the run's own
# (cleanup.sh fresh clones it from the template's), reached through the unix socket the sandbox lets
# through; the toolchain is mise's, as the template pins it. Args: RID WS
rid=$1 ws=$2
tag=$(printf '%s' "$rid" | tr -c 'a-zA-Z0-9' '_' | tr 'A-Z' 'a-z' | cut -c1-40)
trusted=$(dirname "$(dirname "$ws")")
path=$(MISE_TRUSTED_CONFIG_PATHS="$trusted" mise env -C "$ws" --json | jq -r '.PATH')
echo "PATH=$path"
echo "MISE_TRUSTED_CONFIG_PATHS=$trusted"
echo "POSTGRES_URL=postgres://localhost/oban_test_$tag?socket_dir=/run/postgresql"
