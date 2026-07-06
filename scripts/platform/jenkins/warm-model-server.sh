#!/usr/bin/env bash
# Warms a host Ollama endpoint through its OpenAI-compatible API.
# Logs are written to /metrics/warm-model-server.log for Jenkins visibility.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../../../config.env"

MODEL="${MODEL_NAME:?MODEL_NAME must be set in repo-root config.env}"
MODEL_SOURCE="${MODEL_SERVER_MODEL_ID:-${MODEL}}"
MODEL_SERVER_BASE_URL="${MODEL_SERVER_BASE_URL:-http://localhost:11434/v1}"
READY_URL="${MODEL_SERVER_BASE_URL}/models"
WARMUP_LOG="/metrics/warm-model-server.log"

mkdir -p /metrics
exec > >(tee -a "${WARMUP_LOG}") 2>&1

echo "=== Model Server Warmup at $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
echo "Provider: ollama (host)"
echo "Model: ${MODEL}"
echo "Model source: ${MODEL_SOURCE}"
echo "Endpoint: ${MODEL_SERVER_BASE_URL}/chat/completions"
echo "Readiness probe: ${READY_URL}"

echo "Waiting for server readiness..."
MAX_ATTEMPTS=90
WAIT_SECONDS=5
for i in $(seq 1 "${MAX_ATTEMPTS}"); do
    if curl -fsS "${READY_URL}" > /dev/null 2>&1; then
        echo "Status: model server is healthy."
        break
    fi
    echo "[${i}/${MAX_ATTEMPTS}] waiting ${WAIT_SECONDS}s..."
    sleep "${WAIT_SECONDS}"
done

if ! curl -fsS "${READY_URL}" > /dev/null 2>&1; then
    echo "ERROR: host Ollama endpoint did not become healthy in time."
    echo "Make sure Ollama is running on macOS and model '${MODEL_SOURCE}' is pulled."
    exit 1
fi

echo "=== Available models from ${READY_URL} ==="
curl -fsS "${READY_URL}" | tee /tmp/model-server-models.json

payload=$(cat <<EOF
{"model":"${MODEL}","messages":[{"role":"user","content":"ping"}],"max_tokens":4}
EOF
)

if curl -fsS -X POST "${MODEL_SERVER_BASE_URL}/chat/completions" \
    -H "Content-Type: application/json" \
    -d "${payload}" > /tmp/model-server-warmup.json; then
    echo "Status: warmup request succeeded."
    echo "=== Ping response from model server ==="
    cat /tmp/model-server-warmup.json
    echo "======================================="
else
    echo "Status: warmup request failed."
    echo "Ensure '${MODEL_SOURCE}' exists in host Ollama: ollama pull ${MODEL_SOURCE}"
    exit 1
fi

echo "Host Ollama warmup check complete."
