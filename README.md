# semver-analyzer Ansible Playbook

Automates the full semver-analyzer migration pipeline: provisions a Linux VM via Podman, installs all dependencies, analyzes breaking changes between PatternFly versions, and applies fixes to a consumer application.

## Prerequisites

- **Podman** installed on the host (Mac or Linux)
- **Ansible** 2.15+
- A GCP service account key with Vertex AI access

## Quick Start

```bash
cd ansible/

# 1. Create the vault from the example and fill in your credentials
cp group_vars/all/vault.yml.example group_vars/all/vault.yml
# Edit vault.yml — set gcp_project_id and paste your GCP credentials JSON
#   (use the contents of ~/.config/gcloud/application_default_credentials.json)

# 2. Encrypt the vault and set up a password file
ansible-vault encrypt group_vars/all/vault.yml
echo 'your-password' > .vault_password
chmod 600 .vault_password

# 3. Run the full pipeline
ansible-playbook site.yml \
  -e app_repo_url=https://github.com/your-org/your-app.git \
  --ask-vault-pass
```

## Tags

Run selective steps with `--tags`:

| Tag | Role | Description |
|-----|------|-------------|
| `vm` | `podman_vm` | Create and start the Podman machine |
| `system` | `system_deps` | Install system packages via rpm-ostree (triggers reboot) |
| `nodejs` | `nodejs` | Install nvm, Node.js, yarn, and npm packages |
| `rust` | `rust` | Install Rust stable toolchain via rustup |
| `repos` | `clone_repos` | Clone all git repositories |
| `build` | `build_rust` | `cargo build --release` for both Rust binaries |
| `kantra` | `kantra` | Download kantra binary from GitHub releases |
| `goose` | `goose` | Install goose CLI and write GCP credentials |
| `workspace` | `workspace` | Create working directory, symlinks, provider config |
| `analyze` | `semver_analysis` | Run semver-analyzer (async, up to 2h) |
| `rules` | `semver_rules` | Generate Kantra rules and fix strategies |
| `scan` | `kantra_analysis` | Start frontend provider and run kantra |
| `fix` | `apply_fixes` | Create migration branch and apply fixes |
| **`setup`** | all of the above through `workspace` | Full environment setup |
| **`pipeline`** | `analyze` through `fix` | Full analysis and fix pipeline |

```bash
# Setup only
ansible-playbook site.yml -e app_repo_url=... --tags setup --ask-vault-pass

# Run analysis pipeline (assumes setup is done)
ansible-playbook site.yml -e app_repo_url=... --tags pipeline --ask-vault-pass

# Re-run analysis from scratch
ansible-playbook site.yml -e app_repo_url=... --tags analyze,rules -e force_rerun=true --ask-vault-pass

# Only apply fixes
ansible-playbook site.yml -e app_repo_url=... --tags fix --ask-vault-pass
```

## Variables

### Required (no defaults)

| Variable | Passed via | Description |
|----------|-----------|-------------|
| `app_repo_url` | `-e` | Git URL of the consumer application to migrate |

### PatternFly

| Variable | Default | Description |
|----------|---------|-------------|
| `patternfly_from_version` | `v5.4.0` | Source version tag |
| `patternfly_to_version` | `v6.4.0` | Target version tag |
| `app_repo_branch` | `main` | Branch to check out in the app repo |

### VM

| Variable | Default | Description |
|----------|---------|-------------|
| `vm_name` | `semver-pipeline` | Podman machine name |
| `vm_cpus` | `6` | vCPUs allocated |
| `vm_memory` | `8192` | Memory in MiB |
| `vm_disk_size` | `100` | Disk in GiB |

### Node.js

| Variable | Default | Description |
|----------|---------|-------------|
| `node_version` | `20.11.0` | Node.js version installed via nvm |
| `npm_packages` | `[]` | List of `{name, version}` dicts for global npm packages |

### GCP / Goose (in vault.yml)

| Variable | Default | Description |
|----------|---------|-------------|
| `goose_provider` | `gcp_vertex_ai` | Goose LLM provider identifier |
| `goose_model` | `claude-opus-4-6` | Model to use for LLM-assisted fixes |
| `gcp_project_id` | — | GCP project with Vertex AI access |
| `gcp_location` | `us-east5` | GCP region |
| `gcp_service_account_key` | — | GCP credentials JSON (from `~/.config/gcloud/application_default_credentials.json`) |
| `llm_timeout` | `300` | Timeout in seconds per LLM operation (in vars.yml) |

### Other

| Variable | Default | Description |
|----------|---------|-------------|
| `kantra_version` | `latest` | Kantra release tag (or `latest`) |
| `frontend_provider_port` | `9002` | gRPC port for frontend-analyzer-provider |
| `force_rerun` | `false` | Re-run analysis even if outputs exist |

## Idempotency

The playbook is safe to run multiple times:

- **System packages**: Only installed if missing; reboot only when new packages are layered.
- **Tool installs**: Skipped if binary already exists.
- **Git repos**: Updated in place via `ansible.builtin.git`.
- **Cargo builds**: Only recompiles when source changes.
- **Analysis outputs**: Skipped if output files exist (override with `-e force_rerun=true`).
- **Fix application**: Each run creates a new branch (`migration/YYYYMMDDTHHMMSS`) and resets to the base branch before applying, so fixes are never stacked.

## SSH Access

The VM is accessible via `podman machine ssh`:

```bash
podman machine ssh semver-pipeline
```

Or using the SSH details from inspect:

```bash
podman machine inspect semver-pipeline  # shows Port, IdentityPath, RemoteUsername
ssh -i <IdentityPath> -p <Port> core@localhost
```

## Directory Layout (inside VM)

```
/home/core/pipeline/
├── repos/
│   ├── patternfly-react/
│   ├── patternfly/
│   ├── semver-analyzer/
│   ├── frontend-analyzer-provider/
│   └── <app-name>/                   # your application
└── workspace/
    ├── semver-analyzer -> repos/semver-analyzer/target/release/semver-analyzer
    ├── frontend-analyzer-provider -> repos/frontend-analyzer-provider/target/release/...
    ├── provider_settings.json
    └── outputs/
        ├── semver_report.json
        ├── semver_rules/
        ├── fix-guidance/
        └── <app-name>/kantra/
```

## Destroying the VM

```bash
podman machine stop semver-pipeline
podman machine rm semver-pipeline
```
