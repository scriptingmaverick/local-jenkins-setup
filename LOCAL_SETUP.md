# Local Jenkins + Ollama Setup

This folder is a local-ready copy of the pipeline with these changes:

- Uses Ollama (`qwen3:14b`) instead of vLLM.
- Uses host Ollama endpoint for inference on Mac (`host.docker.internal`).
- Removes EKS-specific Kubernetes scheduling constraints.
- Makes Datadog disabled by default.
- Makes GPU checks/metrics optional when `nvidia-smi` is unavailable.

## 1) Prerequisites

- Docker Desktop (or Docker Engine) running.
- Local Kubernetes cluster (`kind`, `k3d`, or `minikube`).
- Jenkins with these plugins:
  - Kubernetes
  - Pipeline
  - Credentials Binding
  - Git
  - HTML Publisher
- Network access from Jenkins pods to:
  - Bitbucket
  - Jira
  - SonarQube

## 2) Jenkins Credentials

Create credentials in Jenkins with exactly these IDs:

- `BITBUCKET_API_KEY` (Username with password)
  - username: Bitbucket user
  - password: Bitbucket PAT/token
- `JIRA_API_TOKEN` (Secret text)
- `SONAR_AUTH_TOKEN` (Secret text)
- `DATADOG_API_KEY` (Secret text, optional if Datadog disabled)

## 3) Kubernetes Cloud in Jenkins

Configure Jenkins -> Manage Jenkins -> Clouds -> Kubernetes:

- Connect Jenkins to your local cluster context.
- Set namespace where agents should run.
- Ensure dynamic pod provisioning is enabled.

The pipeline references this pod template file:

- `scripts/runtime/harness/jenkins-agent-pod.yaml`

## 4) Ollama Model Server Behavior

Inference uses host Ollama (macOS) through:

- `scripts/platform/jenkins/warm-model-server.sh`

It does:

1. Wait for host Ollama endpoint readiness
2. Validate models endpoint
3. Hit `/v1/chat/completions` warmup request

Model settings are in:

- `config.env`

Current local defaults:

- `MODEL_SERVER_PROVIDER=ollama`
- `MODEL_NAME=qwen3:14b`
- `MODEL_SERVER_MODEL_ID=qwen3:14b`
- `MODEL_SERVER_BASE_URL=http://host.docker.internal:11434/v1`

Before running Jenkins build on Mac:

- Start Ollama on host: `ollama serve`
- Pull model on host: `ollama pull qwen3:14b`

## 5) Create and Run the Job

Use a **Pipeline** job and point it to this Jenkinsfile:

- `local-setup/Jenkinsfile`

Recommended first run parameters:

- `BITBUCKET_PROJECT`: your project key
- `BITBUCKET_REPO`: one test repo only
- `GOAL`: small harmless goal
- `DRY_RUN=true`
- `RUN_PREFLIGHT_TESTS=false`
- `ENABLE_DD_METRICS=false`
- `AGENT_HARNESS=opencode` (best first for OpenAI-compatible local models)

Then run the build.

## Same Pipeline + Minimal Pod Footprint

If you want the exact same pipeline stages with lower infra requirements, use:

- Jenkins pipeline file: `local-setup/Jenkinsfile`
- Pod template it already references: `local-setup/scripts/runtime/harness/jenkins-agent-pod.yaml`

This keeps all stages unchanged while reducing only pod/container requirements:

- `jnlp` reduced to lightweight CPU/memory
- `coding-agent` reduced to practical minimum for setup + harness execution
- `model-server` is now a lightweight helper container (inference happens on host Ollama)
- No EKS selectors/tolerations

## 6) Expected Artifacts

On completion, Jenkins archives:

- `pr-summary.txt`
- `agent-logs/**/*`
- `metrics-artifacts/**/*`

## 7) Troubleshooting

- If model warmup fails:
  - Check logs from `Warm Model Server` stage.
  - Verify `MODEL_SERVER_BASE_URL=http://host.docker.internal:11434/v1`.
  - Confirm host Ollama is running and model exists (`ollama list`).
- If clone/auth fails:
  - Recheck `BITBUCKET_API_KEY` format and permissions.
- If GPU checks fail on laptop/CPU nodes:
  - Keep `RUN_PREFLIGHT_TESTS=false`.
  - GPU metrics are auto-skipped when `nvidia-smi` is missing.
- If model pull is slow:
  - Pull once on host before Jenkins run: `ollama pull qwen3:14b`.

