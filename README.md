# semver-analyzer Ansible Playbook

Automates the full semver-analyzer migration pipeline: analyzes breaking changes between PatternFly versions and applies fixes to a consumer application. Runs locally or inside a Podman VM.

## Prerequisites

- **Ansible** 2.15+
- **Podman** (VM mode only)
- GCP credentials for Vertex AI (for LLM-assisted fixes)

### Local mode additional prerequisites

gcc, openssl-devel, pkg-config, Node.js (via nvm), Rust (via rustup), kantra, goose CLI.

## Quick Start

```bash
cd ansible/

# 1. Create your config from an example
cp vars.vm.yml.example my-config.yml    # VM mode
# or
cp vars.local.yml.example my-config.yml # Local mode

# 2. Edit my-config.yml with your values

# 3. Set up the vault
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
# Edit vault.yml with your GCP credentials
ansible-vault encrypt group_vars/all/vault.yml
echo 'your-password' > .vault_password && chmod 600 .vault_password

# 4. Run
ansible-playbook site.yml -e @my-config.yml --tags setup,pipeline
```

## Run Modes

### VM mode (`run_mode: vm`)

Creates a Podman machine, installs all dependencies, clones repos, builds tools, and runs the pipeline inside the VM.

```bash
ansible-playbook site.yml -e @my-config.yml --tags setup,pipeline
```

### Local mode (`run_mode: local`)

Runs directly on the host using existing repo checkouts and tool installations. Skips VM creation, system deps, and repo cloning.

```bash
# Setup (install tools only — skip system, repos, build if already done)
ansible-playbook site.yml -e @my-config.yml --tags workspace,goose,kantra

# Run pipeline
ansible-playbook site.yml -e @my-config.yml --tags pipeline
```

## Tags

| Tag | Role | Description |
|-----|------|-------------|
| `vm` | `podman_vm` | Provision target host (VM or local) |
| `system` | `system_deps` | Install system packages via rpm-ostree (VM only) |
| `nodejs` | `nodejs` | Install nvm, Node.js, yarn |
| `rust` | `rust` | Install Rust stable toolchain |
| `repos` | `clone_repos` | Clone all git repositories (VM only) |
| `build` | `build_rust` | `cargo build --release` for Rust binaries |
| `kantra` | `kantra` | Download kantra binary from GitHub releases |
| `goose` | `goose` | Install goose CLI (+ write GCP credentials in VM mode) |
| `workspace` | `workspace` | Create working directory, symlinks, provider config |
| `analyze` | `semver_analysis` | Run semver-analyzer (async, up to 2h) |
| `rules` | `semver_rules` | Generate Kantra rules and fix strategies |
| `scan` | `kantra_analysis` | Start frontend provider and run kantra |
| `fix` | `apply_fixes` | Create migration branch and apply fixes |
| **`setup`** | all of the above through `workspace` | Full environment setup |
| **`pipeline`** | `analyze` through `fix` | Full analysis and fix pipeline |

```bash
# Re-run analysis from scratch
ansible-playbook site.yml -e @my-config.yml --tags analyze,rules -e force_rerun=true

# Only apply fixes
ansible-playbook site.yml -e @my-config.yml --tags fix
```

## Variables

### Config file (`my-config.yml`)

| Variable | VM default | Local | Description |
|----------|-----------|-------|-------------|
| `run_mode` | `vm` | `local` | Execution mode |
| `app_repo_url` | (required) | — | Git URL of application (VM mode) |
| `app_name` | derived from URL | (required) | Application directory name |
| `app_path` | derived | (required) | Path to application source |
| `app_repo_branch` | `main` | `main` | Base branch for migration |
| `patternfly_from_version` | `v5.4.0` | `v5.4.0` | Source PF version |
| `patternfly_to_version` | `v6.4.1` | `v6.4.1` | Target PF version |
| `patternfly_react_path` | auto | (required) | Path to patternfly-react checkout |
| `patternfly_path` | auto | (required) | Path to patternfly checkout |
| `semver_analyzer_path` | auto | (required) | Path to semver-analyzer checkout |
| `frontend_provider_path` | auto | (required) | Path to frontend-analyzer-provider checkout |
| `workspace_dir` | auto | (required) | Working directory for outputs and symlinks |

### VM-only variables

| Variable | Default | Description |
|----------|---------|-------------|
| `vm_name` | `semver-pipeline` | Podman machine name |
| `vm_cpus` | `6` | vCPUs |
| `vm_memory` | `8192` | Memory in MiB |
| `vm_disk_size` | `100` | Disk in GiB |

### Vault (`group_vars/all/vault.yml`)

| Variable | Description |
|----------|-------------|
| `goose_provider` | Goose LLM provider (e.g. `gcp_vertex_ai`) |
| `goose_model` | Model name (e.g. `claude-opus-4-6`) |
| `gcp_project_id` | GCP project with Vertex AI access |
| `gcp_location` | GCP region (e.g. `us-east5`) |
| `gcp_service_account_key` | GCP credentials JSON |

### Other defaults (`group_vars/all/vars.yml`)

| Variable | Default | Description |
|----------|---------|-------------|
| `node_version` | `20.11.0` | Node.js version |
| `kantra_version` | `latest` | Kantra release tag |
| `llm_timeout` | `300` | Timeout per LLM operation (seconds) |
| `frontend_provider_port` | `9002` | gRPC port for frontend provider |
| `force_rerun` | `false` | Re-run analysis even if outputs exist |

## Idempotency

- **Tool installs**: Skipped if binary already exists.
- **Git repos**: Updated in place (VM mode).
- **Cargo builds**: Only recompiles when source changes.
- **Analysis outputs**: Skipped if output files exist (override with `-e force_rerun=true`).
- **Fix application**: Each run creates a new branch (`migration/YYYYMMDDTHHMMSS`).

## SSH Access (VM mode)

```bash
podman machine ssh semver-pipeline
```

## Destroying the VM

```bash
podman machine stop semver-pipeline
podman machine rm semver-pipeline
```
