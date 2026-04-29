# PatternFly Migration Tools

Automated migration of PatternFly 5 applications to PatternFly 6 using static analysis, pattern-based fixes, LLM-assisted fixes, and AI agent refinement.

## Table of Contents

- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Container Runner (run_container.sh)](#container-runner)
- [Run Modes](#run-modes)
- [Evaluation](#evaluation)
- [Environment Variables](#environment-variables)
- [Logs](#logs)
- [Examples](#examples)
- [Building the Container Image](#building-the-container-image)
- [Running Without Container (run.sh)](#running-without-container)
- [Building Archives (build.sh)](#building-archives)
- [Source Repositories](#source-repositories)

## Quick Start

```bash
# Set GCP credentials
export GCP_PROJECT_ID=my-gcp-project
export GCP_LOCATION=us-east5

# Run migration
./run_container.sh --migrate /path/to/your/app
```

## Prerequisites

| Requirement | Description |
|-------------|-------------|
| Podman or Docker | Container runtime |
| `GCP_PROJECT_ID` | GCP project with Vertex AI access |
| `GCP_LOCATION` | GCP region (e.g., `us-east5`) |
| `~/.config/gcloud/application_default_credentials.json` | GCP Application Default Credentials |

## Container Runner

### CLI Reference (`run_container.sh`)

#### Required

| Option | Description |
|--------|-------------|
| `--migrate <PATH>` | Path to the application to migrate |

#### Optional — Container

| Option | Default | Description |
|--------|---------|-------------|
| `--bake` | off | Bake app into image instead of mounting |
| `--goose-config <PATH>` | baked default | Override goose config directory |
| `--image <NAME>` | `quay.io/pranavgaikwad/patternfly-tools:latest` | Container image |

#### Optional — Migration

| Option | Default | Description |
|--------|---------|-------------|
| `--base-branch <NAME>` | `main` | Branch of the application to migrate |
| `--skip-agent` | off | Skip AI agent step (Phase 2) |
| `--llm-timeout <SECS>` | `300` | LLM timeout per fix |
| `--non-interactive` | off | Skip all prompts |

#### Optional — Evaluation

| Option | Default | Description |
|--------|---------|-------------|
| `--enable-eval` | off | Run evaluation after migration |
| `--eval-only <BRANCH>` | — | Evaluate an existing migrated branch (skips migration) |

## Run Modes

### Mount mode (default)

Mounts the app directory into the container. Changes are applied in real-time on the host.

```bash
./run_container.sh --migrate /path/to/app
```

### Bake mode

Copies the app into a temporary image, runs migration inside it, then syncs results back. Use this when mount performance is slow (e.g., Docker on Mac).

```bash
./run_container.sh --bake --migrate /path/to/app
```

## Migration Pipeline

The migration runs in two phases:

| Phase | Steps | Description |
|-------|-------|-------------|
| **Phase 1** | 1–7 | Automated analysis and fixes |
| **Phase 2** | 8 | AI agent for remaining issues |

### Phase 1 — Automated

| Step | Description |
|------|-------------|
| 1 | Generate provider settings |
| 2 | Start frontend-analyzer-provider |
| 3 | Run kantra static analysis |
| 4 | Stop provider |
| 5 | Convert kantra YAML output to JSON |
| 6 | Apply pattern-based fixes (deterministic) |
| 7 | Apply LLM-based fixes (via Goose + Vertex AI) |

After Phase 1, all changes are committed as "Apply automated migration fixes (pattern-based + LLM)".

### Phase 2 — AI Agent

Step 8 runs Goose to fix remaining build errors, type issues, and test failures. Changes are committed as "Apply AI agent fixes (goose)".

Skip with `--skip-agent`.

## Evaluation

Evaluation compares a migration branch against a pf-codemods baseline and generates an HTML report.

### After migration

```bash
./run_container.sh --enable-eval --migrate /path/to/app
```

### Evaluate an existing branch

```bash
./run_container.sh --eval-only my-migration-branch --migrate /path/to/app
```

The evaluation:
1. Creates a `pf-codemods-MMDDYY-HHMM` branch from the base, runs `npx @patternfly/pf-codemods@latest --v6 --fix`
2. Runs the evaluation agent comparing base → pf-codemods → migration branch
3. Generates `pf-migration-comparison-report.html` in the logs directory
4. Deletes the pf-codemods branch

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `GCP_PROJECT_ID` | Yes | GCP project with Vertex AI access |
| `GCP_LOCATION` | Yes | GCP region |
| `GOOSE_PROVIDER` | No | Override LLM provider (default: `gcp_vertex_ai`) |
| `GOOSE_MODEL` | No | Override model (default: `claude-opus-4-6`) |

GCP credentials at `~/.config/gcloud/` are auto-mounted when present.

## Goose Configuration

The image includes a default Goose config using GCP Vertex AI with Claude. To use your own:

```bash
./run_container.sh --goose-config ~/.config/goose --migrate /path/to/app
```

## Logs

Logs are saved to `.pf-migration-logs/<timestamp>/` in the directory where you run the script.

| File | Contents |
|------|----------|
| `kantra.log` | Static analysis output |
| `provider.log` | Frontend analyzer provider |
| `fix-pattern.log` | Pattern-based fix output |
| `fix-llm.log` | LLM-assisted fix output |
| `agent-goose.log` | AI agent transcript |
| `eval-agent.log` | Evaluation agent transcript (if `--enable-eval`) |
| `pf-migration-comparison-report.html` | Evaluation report (if `--enable-eval`) |

## Examples

### Basic migration

```bash
export GCP_PROJECT_ID=my-project GCP_LOCATION=us-east5
./run_container.sh --migrate ~/code/my-pf5-app
```

### Migrate from a specific branch

```bash
./run_container.sh --migrate ~/code/my-app --base-branch develop
```

### Migration without AI agent (Phase 1 only)

```bash
./run_container.sh --migrate ~/code/my-app --skip-agent
```

### Migration with evaluation

```bash
./run_container.sh --enable-eval --migrate ~/code/my-app
```

### Evaluate an existing migration branch

```bash
./run_container.sh --eval-only semver/goose/042926-1043 --migrate ~/code/my-app
```

### Bake mode with custom goose config

```bash
./run_container.sh --bake --goose-config ~/.config/goose --migrate ~/code/my-app
```

### Use a custom container image

```bash
./run_container.sh --image localhost/semver-runner:latest --migrate ~/code/my-app
```

---

## Building the Container Image

The `Containerfile` uses a 4-stage multi-stage build:

| Stage | Base Image | Purpose |
|-------|-----------|---------|
| 1 | `ubi9/go-toolset` | Build kantra + java-external-provider (Go) |
| 2 | `ubi9/ubi` + rustup | Build semver-analyzer, frontend-analyzer-provider, fix-engine-cli (Rust) |
| 3 | `ubi9/nodejs-20` | Generate pre-packaged migration rules |
| 4 | `ubi9/ubi-minimal` | Runtime with Java, Maven, Goose, yq |

```bash
podman build -t localhost/semver-runner:latest -f Containerfile .
```

### Build args

| Arg | Default | Description |
|-----|---------|-------------|
| `KANTRA_VERSION` | `v0.9.2-rc.1` | Kantra release for assets |
| `PF_REACT_FROM` | `v5.4.0` | PatternFly React source version |
| `PF_REACT_TO` | `v6.4.1` | PatternFly React target version |
| `PF_DEP_FROM` | `v5.4.0` | PatternFly CSS source version |
| `PF_DEP_TO` | `v6.4.0` | PatternFly CSS target version |

---

## Running Without Container

### run.sh

Runs the migration directly on the host. Requires Java JDK, Maven, Goose CLI, yq or python3, git.

| Option | Default | Description |
|--------|---------|-------------|
| `--migrate <PATH>` | — | Project to migrate (required) |
| `--base-branch <NAME>` | `main` | Base branch |
| `--agent <NAME>` | `goose` | AI agent: goose, claude, opencode |
| `--skip-agent` | off | Skip AI agent step |
| `--rules-dir <PATH>` | pre-packaged | Custom rules directory |
| `--llm-timeout <SECS>` | `300` | LLM timeout |
| `--non-interactive` | off | Skip prompts |
| `--generate-rules` | — | Generate new rules instead of migrating |

### eval.sh

Runs evaluation against an existing migrated branch.

| Option | Default | Description |
|--------|---------|-------------|
| `--migrate <PATH>` | — | Project path (required) |
| `--branch <BRANCH>` | — | Migration branch to evaluate (required) |
| `--base-branch <NAME>` | `main` | Base branch |
| `--agent <NAME>` | `goose` | AI agent |
| `--non-interactive` | off | Skip prompts |

---

## Building Archives

For building a distributable ZIP without containers. See `build.sh`.

```bash
./build.sh
```

Prompts for target platform and kantra release. All repo URLs/branches are overridable via environment variables.

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
