# PatternFly Migration Tools

Automated migration of PatternFly 5 applications to PatternFly 6. Runs static analysis, applies pattern-based and LLM-assisted fixes, and optionally invokes an AI agent for remaining issues.

## Quick Start (Container)

The easiest way to run is via the container image. No local tool installation required — just Podman (or Docker) and GCP credentials for Vertex AI.

### Prerequisites

- **Podman** or **Docker**
- **GCP Vertex AI** credentials:
  - `GCP_PROJECT_ID` and `GCP_LOCATION` environment variables
  - Application Default Credentials at `~/.config/gcloud/application_default_credentials.json`

### 1. Build the container image

```bash
cd dist/
podman build -t localhost/semver-runner:latest -f Containerfile .
```

This is a multi-stage build that compiles all tools from source and generates migration rules. Takes 30-60 minutes on first build.

### 2. Run the migration

```bash
export GCP_PROJECT_ID=my-gcp-project
export GCP_LOCATION=us-east5

./run_container.sh --migrate /path/to/your/app
```

This will:
1. Create a git branch `semver/goose/MMDDYY-HHMM` from `main`
2. Run kantra static analysis against pre-generated PatternFly migration rules
3. Apply pattern-based fixes (deterministic)
4. Apply LLM-assisted fixes (via Goose + Vertex AI)
5. Commit automated fixes
6. Run Goose AI agent for remaining build/test fixes
7. Commit agent fixes

Results appear directly in your app directory on the migration branch.

### Container CLI Options

```
./run_container.sh --migrate <PATH> [OPTIONS]

Required:
  --migrate <PATH>           Path to the application to migrate

Container options:
  --bake                     Bake app into image instead of mounting
  --goose-config <PATH>      Override goose config directory
  --image <NAME>             Container image (default: localhost/semver-runner:latest)
  --enable-eval              Run evaluation agent after migration

Options forwarded to run.sh:
  --agent <NAME>             AI agent: goose (default), claude, opencode
  --base-branch <NAME>       Base branch (default: main)
  --non-interactive          Skip all prompts
```

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `GCP_PROJECT_ID` | Yes | GCP project with Vertex AI access |
| `GCP_LOCATION` | Yes | GCP region (e.g., `us-east5`) |
| `GOOSE_PROVIDER` | No | Override LLM provider (default: `gcp_vertex_ai`) |
| `GOOSE_MODEL` | No | Override model (default: `claude-opus-4-6`) |

### Run Modes

**Mount mode** (default):
```bash
./run_container.sh --migrate /path/to/app
```
Mounts your app directory into the container. Changes are applied in real-time.

**Bake mode** (for slow mounts, e.g., Docker on Mac):
```bash
./run_container.sh --bake --migrate /path/to/app
```
Copies the app into a temporary image, runs migration inside it, then syncs results back.

### Goose Configuration

The image includes a default Goose config using GCP Vertex AI with Claude. To override:

```bash
./run_container.sh --goose-config ~/.config/goose --migrate /path/to/app
```

### Evaluation

To run a post-migration evaluation that compares the base branch with the migration branch:

```bash
./run_container.sh --enable-eval --migrate /path/to/app
```

This runs an evaluation agent that generates `pf-migration-comparison-report.html` in the logs directory.

### Logs

Logs are saved to `.pf-migration-logs/` in the directory where you run the script:

| File | Contents |
|------|----------|
| `kantra.log` | Static analysis output |
| `provider.log` | Frontend analyzer provider |
| `fix-pattern.log` | Pattern-based fix output |
| `fix-llm.log` | LLM-assisted fix output |
| `agent-goose.log` | AI agent transcript |
| `eval-agent.log` | Evaluation agent transcript (if `--enable-eval`) |
| `pf-migration-comparison-report.html` | Evaluation report (if `--enable-eval`) |

### Examples

Basic migration:
```bash
export GCP_PROJECT_ID=my-project GCP_LOCATION=us-east5
./run_container.sh --migrate ~/code/my-pf5-app
```

Migration from a specific branch:
```bash
./run_container.sh --migrate ~/code/my-app --base-branch develop
```

Migration with evaluation:
```bash
./run_container.sh --migrate ~/code/my-app --enable-eval
```

Bake mode with custom goose config:
```bash
./run_container.sh --bake --goose-config ~/.config/goose --migrate ~/code/my-app
```

---

## Building the Container Image

The `Containerfile` uses a multi-stage build:

| Stage | Base Image | Purpose |
|-------|-----------|---------|
| 1 | `ubi9/go-toolset` | Build kantra + java-external-provider (Go) |
| 2 | `ubi9/ubi` + rustup | Build semver-analyzer, frontend-analyzer-provider, fix-engine-cli (Rust) |
| 3 | `ubi9/nodejs-20` | Generate pre-packaged migration rules |
| 4 | `ubi9/ubi-minimal` | Runtime with Java, Maven, Goose, yq |

### Build Args

Override PatternFly versions or repo URLs at build time:

```bash
podman build \
  --build-arg PF_REACT_FROM=v5.4.0 \
  --build-arg PF_REACT_TO=v6.4.1 \
  --build-arg KANTRA_VERSION=v0.9.2-rc.1 \
  -t localhost/semver-runner:latest \
  -f Containerfile .
```

---

## Building Without Container (build.sh)

For building a distributable ZIP archive with platform-specific binaries.

### Prerequisites

| Tool | Install |
|------|---------|
| go | https://go.dev/dl/ |
| cargo + rustup | https://rustup.rs/ |
| git, curl, unzip, python3 | System package manager |
| nvm | https://github.com/nvm-sh/nvm |

### Usage

```bash
./build.sh
```

Prompts for target platform and kantra release, then builds everything and packages as `patternfly_tools_<platform>.zip`.

### Overriding Repos

All repo URLs and branches are overridable via environment variables:

```bash
SEMVER_REPO_URL=https://github.com/my-fork/semver-analyzer.git \
SEMVER_REPO_BRANCH=my-branch \
./build.sh
```

---

## Running Without Container (run.sh)

The `run.sh` script can run directly on the host if all tools are installed:

```bash
./run.sh --migrate /path/to/app --agent goose
```

Requires: Java JDK, Maven, Goose CLI, yq or python3, git.

See `./run.sh --help` for all options.

---

## Source Repositories

| Repo | Purpose |
|------|---------|
| [konveyor/kantra](https://github.com/konveyor/kantra) | Static analysis CLI |
| [konveyor/analyzer-lsp](https://github.com/konveyor/analyzer-lsp) | java-external-provider |
| [shawn-hurley/semver-analyzer](https://github.com/shawn-hurley/semver-analyzer) | Breaking change detection |
| [shawn-hurley/konveyor-core](https://github.com/shawn-hurley/konveyor-core) | Shared Konveyor types |
| [shawn-hurley/frontend-analyzer-provider](https://github.com/shawn-hurley/frontend-analyzer-provider) | Frontend analysis provider |
| [shawn-hurley/fix-engine](https://github.com/shawn-hurley/fix-engine) | Fix engine CLI |
| [patternfly/patternfly-react](https://github.com/patternfly/patternfly-react) | PatternFly React (analyzed) |
| [patternfly/patternfly](https://github.com/patternfly/patternfly) | PatternFly CSS (analyzed) |
