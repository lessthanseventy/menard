#!/usr/bin/env bash
# Per run: KEY=VALUE lines the agent and its check run under. Databases of the run's own (the test
# one through MIX_TEST_PARTITION, config/test.exs; the dev one through the line build.sh put in
# config/dev.exs), the LLM backend a dead URL with no key (the operator's key never reaches a run,
# and no test may depend on ollama.com), and ssh/scp/podman stubs first on PATH: the project's mise
# tasks deploy to production (myelin.us) through them. The toolchain is the project's, through mise.
# Args: RID WS
rid=$1 ws=$2
tag=$(printf '%s' "$rid" | tr -c 'a-zA-Z0-9' '_' | tr 'A-Z' 'a-z' | cut -c1-40)
here=$(cd "$(dirname "$0")" && pwd)
trusted=$(dirname "$(dirname "$ws")")
path=$(MISE_TRUSTED_CONFIG_PATHS="$trusted" mise env -C "$ws" --json | jq -r '.PATH')
echo "PATH=$here/stubs:$path"
echo "MISE_TRUSTED_CONFIG_PATHS=$trusted"
echo "MIX_TEST_PARTITION=_$tag"
echo "EX_RIVERSIDE_DEV_DB=ex_riverside_dev_$tag"
echo "AI_BASE_URL=http://127.0.0.1:9/v1"
echo "AI_API_KEY="
