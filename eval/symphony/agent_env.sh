#!/usr/bin/env bash
# Per run: KEY=VALUE lines the agent and its check run under: the project's toolchain, through mise.
# Args: RID WS
ws=$2
trusted=$(dirname "$(dirname "$ws")")
path=$(MISE_TRUSTED_CONFIG_PATHS="$trusted" mise env -C "$ws" --json | jq -r '.PATH')
echo "PATH=$path"
echo "MISE_TRUSTED_CONFIG_PATHS=$trusted"
