# PatternFly Migration Tools — Build Script

Builds a self-contained distributable archive containing all binaries, pre-generated rules, and the migration runner for a target platform.

## Prerequisites

| Tool | Purpose | Install |
|------|---------|---------|
| go | Build kantra and java-external-provider | https://go.dev/dl/ |
| cargo + rustup | Build Rust binaries | https://rustup.rs/ |
| git | Clone source repos | System package manager |
| curl | Download releases | System package manager |
| unzip | Extract kantra release | System package manager |
| python3 | Kantra release selection | System package manager |
| nvm | Node.js for rule generation | https://github.com/nvm-sh/nvm |

For cross-compilation (building for a different platform):
- [cargo-zigbuild](https://github.com/rust-cross/cargo-zigbuild): `cargo install cargo-zigbuild`
- [llvm](https://llvm.org/) (provides `llvm-ar` for cross-compile of C dependencies): `brew install llvm`

## Usage

```bash
cd dist/
./build.sh
```

The script prompts for:
1. **Target platform**: Linux_x86, Linux_arm64, Mac_x86, Mac_arm64
2. **Kantra release**: Selects from available GitHub releases

## Overriding Repo URLs and Branches

All source repo URLs and branches can be overridden via environment variables:

```bash
SEMVER_REPO_URL=https://github.com/my-fork/semver-analyzer.git \
SEMVER_REPO_BRANCH=my-branch \
./build.sh
```

| Variable | Default |
|----------|---------|
| `KANTRA_REPO_URL` / `KANTRA_REPO_BRANCH` | konveyor/kantra |
| `SEMVER_REPO_URL` / `SEMVER_REPO_BRANCH` | pranavgaikwad/semver-analyzer, feature/java-feature-flag |
| `KONVEYOR_CORE_REPO_URL` / `KONVEYOR_CORE_REPO_BRANCH` | shawn-hurley/konveyor-core |
| `FAP_REPO_URL` / `FAP_REPO_BRANCH` | shawn-hurley/frontend-analyzer-provider |
| `FIX_ENGINE_REPO_URL` / `FIX_ENGINE_REPO_BRANCH` | shawn-hurley/fix-engine |
| `ANALYZER_LSP_REPO_URL` / `ANALYZER_LSP_REPO_BRANCH` | konveyor/analyzer-lsp |
| `PF_REACT_REPO_URL` | patternfly/patternfly-react |
| `PF_REPO_URL` | patternfly/patternfly |
| `TOKEN_MAPPINGS_URL` | Raw from semver-analyzer repo |

## Build Steps (13 total)

| Step | Description |
|------|-------------|
| 1 | Select kantra release |
| 2 | Download kantra release assets (JDT, rulesets, etc.) |
| 3 | Build kantra from source (Go) |
| 4 | Build java-external-provider from analyzer-lsp (Go) |
| 5 | Build semver-analyzer (Rust, without Java feature) |
| 6 | Build semver-analyzer for host (if cross-compiling) |
| 7 | Build frontend-analyzer-provider + fix-engine-cli (Rust) |
| 8 | Download token mappings |
| 9 | Generate pre-packaged rules (runs semver analysis) |
| 10 | Copy prompt.md |
| 11 | Generate MANIFEST |
| 12 | Copy run.sh and README.md |
| 13 | Package zip archive |

## Output

```
dist/patternfly_tools_<platform>.zip
```

The archive contains everything needed to run migrations — see the [runner README](README.run.md) for usage.

## Build Logs

Per-step log files are created during the build and included in the archive under `logs/`:

| Log file | Contents |
|----------|----------|
| `download-kantra.log` | Kantra release download and extraction |
| `build-kantra.log` | Kantra Go build |
| `build-java-provider.log` | java-external-provider Go build |
| `build-semver-analyzer.log` | semver-analyzer Rust build |
| `build-frontend-analyzer-provider.log` | FAP Rust build |
| `build-fix-engine-cli.log` | fix-engine-cli Rust build |
| `clone-semver.log` | Cloning semver-analyzer and konveyor-core |
| `clone-fap.log` | Cloning FAP and fix-engine |
| `clone-patternfly.log` | Cloning patternfly-react and patternfly |
| `semver-analyze.log` | semver-analyzer analysis output |
| `semver-konveyor.log` | Konveyor rule generation output |

## MANIFEST

The archive includes a `MANIFEST` file with build metadata:
- Build date and target platform
- Git SHAs of all source repositories
- PatternFly version range used for rule generation
- Number of rules generated

## Cross-Compilation

When the target platform differs from the host, the script:
- Uses `cargo-zigbuild` for Rust binaries (falls back to plain `cargo`)
- Uses `GOOS`/`GOARCH` for Go binaries
- Builds a separate host semver-analyzer binary for rule generation

## Source Repositories

| Repo | Purpose |
|------|---------|
| [konveyor/kantra](https://github.com/konveyor/kantra) | Static analysis CLI |
| [konveyor/analyzer-lsp](https://github.com/konveyor/analyzer-lsp) | java-external-provider |
| [shawn-hurley/semver-analyzer](https://github.com/shawn-hurley/semver-analyzer) | Breaking change detection |
| [shawn-hurley/konveyor-core](https://github.com/shawn-hurley/konveyor-core) | Shared Konveyor types |
| [shawn-hurley/frontend-analyzer-provider](https://github.com/shawn-hurley/frontend-analyzer-provider) | Frontend analysis provider |
| [shawn-hurley/fix-engine](https://github.com/shawn-hurley/fix-engine) | Fix engine CLI |
| [patternfly/patternfly-react](https://github.com/patternfly/patternfly-react) | PatternFly React (analyzed for rules) |
| [patternfly/patternfly](https://github.com/patternfly/patternfly) | PatternFly CSS (analyzed for rules) |
