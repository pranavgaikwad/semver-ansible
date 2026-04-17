#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colors ───────────────────────────────────────────────────────────────
if [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
fi

# ── Platform lookups (bash 3.x compatible) ───────────────────────────────
platform_lookup() {
    local field="$1" platform="$2"
    case "$field:$platform" in
        kantra_suffix:Linux_x86)   echo "linux.amd64" ;;
        kantra_suffix:Linux_arm64) echo "linux.arm64" ;;
        kantra_suffix:Mac_x86)     echo "darwin.amd64" ;;
        kantra_suffix:Mac_arm64)   echo "darwin.arm64" ;;
        rust_target:Linux_x86)     echo "x86_64-unknown-linux-gnu" ;;
        rust_target:Linux_arm64)   echo "aarch64-unknown-linux-gnu" ;;
        rust_target:Mac_x86)       echo "x86_64-apple-darwin" ;;
        rust_target:Mac_arm64)     echo "aarch64-apple-darwin" ;;
        go_os:Linux_*)             echo "linux" ;;
        go_os:Mac_*)               echo "darwin" ;;
        go_arch:*_x86)             echo "amd64" ;;
        go_arch:*_arm64)           echo "arm64" ;;
        *) echo "" ;;
    esac
}

# ── Repo defaults ────────────────────────────────────────────────────────
KANTRA_REPO_URL="https://github.com/konveyor/kantra.git"
KANTRA_REPO_BRANCH=""
SEMVER_REPO_URL="https://github.com/pranavgaikwad/semver-analyzer.git"
SEMVER_REPO_BRANCH="feature/java-feature-flag"
KONVEYOR_CORE_REPO_URL="https://github.com/shawn-hurley/konveyor-core.git"
KONVEYOR_CORE_REPO_BRANCH=""
FAP_REPO_URL="https://github.com/shawn-hurley/frontend-analyzer-provider.git"
FAP_REPO_BRANCH=""
FIX_ENGINE_REPO_URL="https://github.com/shawn-hurley/fix-engine.git"
FIX_ENGINE_REPO_BRANCH=""
ANALYZER_LSP_REPO_URL="https://github.com/konveyor/analyzer-lsp.git"
ANALYZER_LSP_REPO_BRANCH=""
PF_REACT_REPO_URL="https://github.com/patternfly/patternfly-react.git"
PF_REPO_URL="https://github.com/patternfly/patternfly.git"
TOKEN_MAPPINGS_URL="https://raw.githubusercontent.com/pranavgaikwad/semver-analyzer/refs/heads/feature/java-feature-flag/hack/integration/patternfly-token-mappings.yaml"

# ── State ────────────────────────────────────────────────────────────────
HOST_PLATFORM=""
TARGET_PLATFORM=""
CROSS_COMPILE=false
KANTRA_VERSION=""
BUILD_ROOT=""
BUILD_DIR=""
BUILD_TMP=""
HOST_SEMVER_BIN=""

# ── Utilities ────────────────────────────────────────────────────────────
info()  { printf "${GREEN}[INFO]${NC}  %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
step()  { printf "\n${BLUE}[STEP %s]${NC} %s\n" "$1" "$2"; }
die()   { error "$@"; exit 1; }

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

git_clone() {
    local url="$1" dest="$2" branch="${3:-}" logfile="${4:-/dev/null}" depth="${5:-}"
    local args=""
    [[ -n "$depth" ]] && args="--depth $depth"
    [[ -n "$branch" ]] && args="$args --branch $branch"
    # shellcheck disable=SC2086
    git clone $args "$url" "$dest" >> "$logfile" 2>&1
}

prompt_select() {
    local prompt="$1"; shift
    local i=1 choice=""
    for opt in "$@"; do
        printf "  %d) %s\n" "$i" "$opt" >&2
        i=$((i + 1))
    done
    printf "${BOLD}%s${NC} [1]: " "$prompt" >&2
    read -r choice
    choice="${choice:-1}"
    i=1
    for opt in "$@"; do
        if [[ "$i" -eq "$choice" ]]; then
            echo "$opt"
            return
        fi
        i=$((i + 1))
    done
    echo "$1"
}

# ── Prerequisites ────────────────────────────────────────────────────────
check_build_prerequisites() {
    info "Checking build prerequisites..."
    local errors=()

    if ! command -v go >/dev/null 2>&1; then
        errors+=("go not found. Install from https://go.dev/dl/")
    fi
    if ! command -v cargo >/dev/null 2>&1; then
        errors+=("cargo not found. Install Rust from https://rustup.rs/")
    fi
    if ! command -v rustup >/dev/null 2>&1; then
        errors+=("rustup not found. Install from https://rustup.rs/ (needed for cross-compile targets)")
    fi
    if ! command -v git >/dev/null 2>&1; then
        errors+=("git not found. Install git.")
    fi
    if ! command -v curl >/dev/null 2>&1; then
        errors+=("curl not found. Install curl.")
    fi
    if ! command -v unzip >/dev/null 2>&1; then
        errors+=("unzip not found. Install unzip.")
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        errors+=("python3 not found. Needed for kantra release selection.")
    fi

    local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
    if [[ ! -f "$nvm_dir/nvm.sh" ]]; then
        errors+=("nvm not found. Needed for rule generation. Install from https://github.com/nvm-sh/nvm")
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        error "Missing build prerequisites:"
        for e in "${errors[@]}"; do
            error "  - $e"
        done
        exit 1
    fi

    if ! command -v cross >/dev/null 2>&1; then
        if ! command -v cargo-zigbuild >/dev/null 2>&1; then
            warn "Neither cross nor cargo-zigbuild found. Cross-compilation will use plain cargo (may fail without a C linker for the target)."
            warn "  Install: cargo install cargo-zigbuild"
        fi
    fi

    info "All build prerequisites satisfied"
}

# ── Platform detection ───────────────────────────────────────────────────
detect_host_platform() {
    local os arch
    os="$(uname -s)"
    arch="$(uname -m)"

    case "$os" in
        Linux)
            case "$arch" in
                x86_64)  HOST_PLATFORM="Linux_x86" ;;
                aarch64) HOST_PLATFORM="Linux_arm64" ;;
                *)       die "Unsupported Linux architecture: $arch" ;;
            esac ;;
        Darwin)
            case "$arch" in
                x86_64)  HOST_PLATFORM="Mac_x86" ;;
                arm64)   HOST_PLATFORM="Mac_arm64" ;;
                *)       die "Unsupported macOS architecture: $arch" ;;
            esac ;;
        *) die "Unsupported OS: $os" ;;
    esac

    info "Host platform: $HOST_PLATFORM"
}

select_platform() {
    printf "\n${BOLD}Select target platform:${NC}\n" >&2
    TARGET_PLATFORM=$(prompt_select "Choose platform" "Linux_x86" "Linux_arm64" "Mac_x86" "Mac_arm64")
    info "Target platform: $TARGET_PLATFORM"

    if [[ "$TARGET_PLATFORM" == "$HOST_PLATFORM" ]]; then
        CROSS_COMPILE=false
        info "Target matches host — native compilation"
    else
        CROSS_COMPILE=true
        info "Cross-compiling for $TARGET_PLATFORM"
    fi
}

# ── Kantra ───────────────────────────────────────────────────────────────
select_kantra_release() {
    step "1/13" "Selecting kantra release"
    info "Querying GitHub for kantra releases..."

    local suffix
    suffix=$(platform_lookup kantra_suffix "$TARGET_PLATFORM")
    local tags
    tags=$(curl -sS "https://api.github.com/repos/konveyor/kantra/releases?per_page=20" | \
        python3 -c "
import json, sys
releases = json.load(sys.stdin)
count = 0
for r in releases:
    assets = [a['name'] for a in r.get('assets', [])]
    if any('$suffix' in a for a in assets):
        print(r['tag_name'])
        count += 1
        if count >= 3:
            break
" 2>/dev/null)

    if [[ -z "$tags" ]]; then
        die "No kantra releases found with assets for $suffix"
    fi

    printf "\n${BOLD}Available kantra releases:${NC}\n" >&2
    # shellcheck disable=SC2086
    KANTRA_VERSION=$(prompt_select "Choose release" $tags)
    info "Selected: $KANTRA_VERSION"
}

download_kantra() {
    step "2/13" "Downloading kantra release"

    local suffix
    suffix=$(platform_lookup kantra_suffix "$TARGET_PLATFORM")
    local url="https://github.com/konveyor/kantra/releases/download/${KANTRA_VERSION}/kantra.${suffix}.zip"
    local zip_path="$BUILD_TMP/kantra.zip"

    mkdir -p "$BUILD_DIR/.kantra"

    local log="$BUILD_TMP/download-kantra.log"
    info "Follow logs: tail -f $log"
    info "Downloading $url"
    curl -fSL -o "$zip_path" "$url" >> "$log" 2>&1 || die "Failed to download kantra. Check $log"

    info "Extracting to .kantra/"
    unzip -o "$zip_path" -d "$BUILD_DIR/.kantra/" >> "$log" 2>&1 \
        || die "Failed to extract kantra release. Check $log"

    if [[ -f "$BUILD_DIR/.kantra/darwin-kantra" ]]; then
        mv "$BUILD_DIR/.kantra/darwin-kantra" "$BUILD_DIR/.kantra/kantra"
    fi

    chmod +x "$BUILD_DIR/.kantra/kantra" "$BUILD_DIR/.kantra/java-external-provider" 2>/dev/null || true

    : > "$BUILD_DIR/.kantra/maven-index.txt"
    info "Created empty maven-index.txt"

    rm "$zip_path"
}

build_kantra_from_source() {
    step "3/13" "Building kantra from source (Go)"

    local kantra_src="$BUILD_TMP/kantra-src"

    local log="$BUILD_TMP/build-kantra.log"
    info "Follow logs: tail -f $log"

    info "Cloning konveyor/kantra..."
    git_clone "$KANTRA_REPO_URL" "$kantra_src" "$KANTRA_REPO_BRANCH" "$log" 1 \
        || die "Failed to clone kantra. Check $log"

    local goos goarch
    goos=$(platform_lookup go_os "$TARGET_PLATFORM")
    goarch=$(platform_lookup go_arch "$TARGET_PLATFORM")

    info "Building for ${goos}/${goarch}..."
    (
        cd "$kantra_src"
        GOOS="$goos" GOARCH="$goarch" CGO_ENABLED=0 \
        go build -o "$BUILD_DIR/.kantra/kantra" main.go
    ) >> "$log" 2>&1 || die "Failed to build kantra. Check $log"

    chmod +x "$BUILD_DIR/.kantra/kantra"
    info "kantra binary built"
}

build_java_external_provider() {
    step "4/13" "Building java-external-provider from analyzer-lsp"

    local analyzer_src="$BUILD_TMP/analyzer-lsp"

    local log="$BUILD_TMP/build-java-provider.log"
    info "Follow logs: tail -f $log"

    info "Cloning konveyor/analyzer-lsp..."
    git_clone "$ANALYZER_LSP_REPO_URL" "$analyzer_src" "$ANALYZER_LSP_REPO_BRANCH" "$log" 1 \
        || die "Failed to clone analyzer-lsp. Check $log"

    local goos goarch
    goos=$(platform_lookup go_os "$TARGET_PLATFORM")
    goarch=$(platform_lookup go_arch "$TARGET_PLATFORM")

    info "Building java-external-provider for ${goos}/${goarch}..."
    (
        cd "$analyzer_src/external-providers/java-external-provider"
        GOOS="$goos" GOARCH="$goarch" CGO_ENABLED=0 \
        go build -o "$BUILD_DIR/.kantra/java-external-provider" main.go
    ) >> "$log" 2>&1 || die "Failed to build java-external-provider. Check $log"

    chmod +x "$BUILD_DIR/.kantra/java-external-provider"
    info "java-external-provider built"
}

# ── Rust builds ──────────────────────────────────────────────────────────
rust_build() {
    local name="$1" src_dir="$2" output_binary="$3" target="$4"

    local log="$BUILD_TMP/build-${name}.log"
    info "Building $name for $target..."
    info "Follow logs: tail -f $log"

    local build_cmd
    if [[ "$CROSS_COMPILE" == true ]]; then
        if command -v cross >/dev/null 2>&1; then
            build_cmd="cross build --release --target $target"
        elif command -v cargo-zigbuild >/dev/null 2>&1; then
            build_cmd="cargo zigbuild --release --target $target"
        else
            build_cmd="cargo build --release --target $target"
        fi
    else
        build_cmd="cargo build --release --target $target"
    fi

    (cd "$src_dir" && $build_cmd) >> "$log" 2>&1 || die "Failed to build $name. Check $log"

    local binary_path="$src_dir/target/$target/release/$name"
    if [[ ! -f "$binary_path" ]]; then
        die "Expected binary not found: $binary_path"
    fi

    cp "$binary_path" "$output_binary"
    chmod +x "$output_binary"
    info "$name built successfully"
}

build_semver_analyzer() {
    step "5/13" "Building semver-analyzer"

    local semver_src="$BUILD_TMP/semver-analyzer"
    local konveyor_core_src="$BUILD_TMP/konveyor-core"

    local log="$BUILD_TMP/clone-semver.log"
    info "Follow logs: tail -f $log"

    info "Cloning konveyor-core (path dependency)..."
    git_clone "$KONVEYOR_CORE_REPO_URL" "$konveyor_core_src" "$KONVEYOR_CORE_REPO_BRANCH" "$log" \
        || die "Failed to clone konveyor-core. Check $log"

    info "Cloning semver-analyzer..."
    git_clone "$SEMVER_REPO_URL" "$semver_src" "$SEMVER_REPO_BRANCH" "$log" \
        || die "Failed to clone semver-analyzer. Check $log"

    local target
    target=$(platform_lookup rust_target "$TARGET_PLATFORM")
    mkdir -p "$BUILD_DIR/bin"

    rust_build "semver-analyzer" "$semver_src" "$BUILD_DIR/bin/semver-analyzer" "$target"
}

build_host_semver_analyzer() {
    if [[ "$CROSS_COMPILE" == false ]]; then
        HOST_SEMVER_BIN="$BUILD_DIR/bin/semver-analyzer"
        info "Using target binary as host binary (same platform)"
        return
    fi

    step "6/13" "Building semver-analyzer for host (needed for rule generation)"

    local semver_src="$BUILD_TMP/semver-analyzer"
    local host_target
    host_target=$(platform_lookup rust_target "$HOST_PLATFORM")

    HOST_SEMVER_BIN="$BUILD_TMP/semver-analyzer-host"
    rust_build "semver-analyzer" "$semver_src" "$HOST_SEMVER_BIN" "$host_target"
}

build_frontend_analyzer_provider() {
    step "7/13" "Building frontend-analyzer-provider"

    local fap_src="$BUILD_TMP/frontend-analyzer-provider"

    local log="$BUILD_TMP/clone-fap.log"
    info "Follow logs: tail -f $log"

    info "Cloning fix-engine (path dependency)..."
    git_clone "$FIX_ENGINE_REPO_URL" "$BUILD_TMP/fix-engine" "$FIX_ENGINE_REPO_BRANCH" "$log" \
        || die "Failed to clone fix-engine. Check $log"

    info "Cloning frontend-analyzer-provider..."
    git_clone "$FAP_REPO_URL" "$fap_src" "$FAP_REPO_BRANCH" "$log" \
        || die "Failed to clone frontend-analyzer-provider. Check $log"

    local target
    target=$(platform_lookup rust_target "$TARGET_PLATFORM")

    rust_build "frontend-analyzer-provider" "$fap_src" "$BUILD_DIR/bin/frontend-analyzer-provider" "$target"

    local fix_engine_src="$BUILD_TMP/fix-engine"
    rust_build "fix-engine-cli" "$fix_engine_src" "$BUILD_DIR/bin/fix-engine-cli" "$target"

    info "fix-engine-cli built"
}

# ── Pre-packaged rules ───────────────────────────────────────────────────
generate_prepackaged_rules() {
    step "9/13" "Generating pre-packaged rules"

    local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
    if [[ ! -f "$nvm_dir/nvm.sh" ]]; then
        die "nvm required for rule generation. Install from https://github.com/nvm-sh/nvm"
    fi

    local pf_react_src="$BUILD_TMP/patternfly-react"
    local pf_src="$BUILD_TMP/patternfly"

    local clone_log="$BUILD_TMP/clone-patternfly.log"

    if [[ ! -d "$pf_react_src/.git" ]]; then
        info "Cloning patternfly-react..."
        git_clone "$PF_REACT_REPO_URL" "$pf_react_src" "" "$clone_log" \
            || die "Failed to clone patternfly-react. Check $clone_log"
    fi

    if [[ ! -d "$pf_src/.git" ]]; then
        info "Cloning patternfly..."
        git_clone "$PF_REPO_URL" "$pf_src" "" "$clone_log" \
            || die "Failed to clone patternfly. Check $clone_log"
    fi

    local pf_from pf_to dep_from dep_to
    pf_from=$(cd "$pf_react_src" && git tag -l 'v5.*' --sort=-v:refname | head -1)
    pf_to=$(cd "$pf_react_src" && git tag -l 'v6.*' --sort=-v:refname | head -1)
    dep_from=$(cd "$pf_src" && git tag -l 'v5.*' --sort=-v:refname | head -1)
    dep_to=$(cd "$pf_src" && git tag -l 'v6.*' --sort=-v:refname | head -1)

    info "patternfly-react: $pf_from -> $pf_to"
    info "patternfly:       $dep_from -> $dep_to"

    local dep_build_cmd="source ~/.nvm/nvm.sh && nvm exec 20.11.0 bash -c 'export NODE_ENV=development && yarn install && npx gulp buildPatternfly'"

    local analyze_log="$BUILD_TMP/semver-analyze.log"
    local konveyor_log="$BUILD_TMP/semver-konveyor.log"

    info "Running semver-analyzer analyze..."
    info "Log: $analyze_log"
    info "Running '$HOST_SEMVER_BIN analyze typescript --repo $pf_react_src --from $pf_from --to $pf_to --no-llm'"
    "$HOST_SEMVER_BIN" analyze typescript \
        --repo "$pf_react_src" \
        --from "$pf_from" \
        --to "$pf_to" \
        --dep-repo "$pf_src" \
        --dep-from "$dep_from" \
        --dep-to "$dep_to" \
        --dep-build-command "$dep_build_cmd" \
        --build-command 'corepack yarn build' \
        --no-llm \
        --log-file "$analyze_log" \
        --log-level info \
        -o "$BUILD_TMP/semver_report.json" \
        > "$analyze_log.stdout" 2>&1 || die "semver-analyzer analyze failed. Check $analyze_log"

    info "Running semver-analyzer konveyor..."
    info "Follow logs: tail -f $konveyor_log"
    mkdir -p "$BUILD_DIR/rules/semver_rules"

    local rename_args=""
    if [[ -f "$BUILD_DIR/patternfly-token-mappings.yaml" ]]; then
        rename_args="--rename-patterns $BUILD_DIR/patternfly-token-mappings.yaml"
    fi

    # shellcheck disable=SC2086
    "$HOST_SEMVER_BIN" konveyor typescript \
        --from-report "$BUILD_TMP/semver_report.json" \
        --output-dir "$BUILD_DIR/rules/semver_rules" \
        --log-file "$konveyor_log" \
        --log-level info \
        $rename_args \
        > "$konveyor_log.stdout" 2>&1 || die "semver-analyzer konveyor failed. Check $konveyor_log"

    # konveyor writes fix-guidance as sibling of output-dir, which is already $BUILD_DIR/rules/fix-guidance
    if [[ -d "$BUILD_DIR/rules/fix-guidance" ]]; then
        info "fix-guidance generated at $BUILD_DIR/rules/fix-guidance/"
    fi

    local rule_count=0
    if [[ -f "$BUILD_DIR/rules/semver_rules/breaking-changes.yaml" ]]; then
        rule_count=$(grep -c 'ruleID:' "$BUILD_DIR/rules/semver_rules/breaking-changes.yaml" || echo 0)
    fi
    info "Rules generated: $rule_count"

    # Store metadata for MANIFEST
    MANIFEST_PF_REACT_FROM="$pf_from"
    MANIFEST_PF_REACT_TO="$pf_to"
    MANIFEST_PF_DEP_FROM="$dep_from"
    MANIFEST_PF_DEP_TO="$dep_to"
    MANIFEST_RULE_COUNT="$rule_count"
}

# ── Extras ───────────────────────────────────────────────────────────────
download_token_mappings() {
    step "8/13" "Downloading token mappings (before rule generation)"

    curl -fSL -o "$BUILD_DIR/patternfly-token-mappings.yaml" "$TOKEN_MAPPINGS_URL" \
        >> "$BUILD_TMP/download-token-mappings.log" 2>&1 || die "Failed to download token mappings"

    info "Downloaded patternfly-token-mappings.yaml"
}

copy_prompt() {
    step "10/13" "Copying prompt.md"

    cp "$SCRIPT_DIR/prompt.md" "$BUILD_DIR/prompt.md" \
        || die "prompt.md not found in $SCRIPT_DIR"
    info "Copied prompt.md"
}

git_sha() {
    local repo_dir="$1"
    if [[ -d "$repo_dir/.git" ]]; then
        git -C "$repo_dir" rev-parse --short HEAD 2>/dev/null || echo "unknown"
    else
        echo "unknown"
    fi
}

generate_manifest() {
    step "11/13" "Generating MANIFEST"

    local build_date
    build_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > "$BUILD_DIR/MANIFEST" <<MANIFEST
# PatternFly Migration Tools
# Generated: ${build_date}

[build]
platform = ${TARGET_PLATFORM}
build_date = ${build_date}

[kantra]
release_version = ${KANTRA_VERSION}
source_sha = $(git_sha "$BUILD_TMP/kantra-src")

[analyzer-lsp]
source_sha = $(git_sha "$BUILD_TMP/analyzer-lsp")

[semver-analyzer]
source_sha = $(git_sha "$BUILD_TMP/semver-analyzer")

[frontend-analyzer-provider]
source_sha = $(git_sha "$BUILD_TMP/frontend-analyzer-provider")

[fix-engine]
source_sha = $(git_sha "$BUILD_TMP/fix-engine")

[konveyor-core]
source_sha = $(git_sha "$BUILD_TMP/konveyor-core")

[rules]
patternfly_react_from = ${MANIFEST_PF_REACT_FROM:-}
patternfly_react_to = ${MANIFEST_PF_REACT_TO:-}
patternfly_dep_from = ${MANIFEST_PF_DEP_FROM:-}
patternfly_dep_to = ${MANIFEST_PF_DEP_TO:-}
rule_count = ${MANIFEST_RULE_COUNT:-0}
patternfly_react_sha = $(git_sha "$BUILD_TMP/patternfly-react")
patternfly_sha = $(git_sha "$BUILD_TMP/patternfly")
MANIFEST

    info "MANIFEST written"
    cat "$BUILD_DIR/MANIFEST"
}

copy_run_script() {
    step "12/13" "Copying run.sh"

    cp "$SCRIPT_DIR/run.sh" "$BUILD_DIR/run.sh"
    chmod +x "$BUILD_DIR/run.sh"
    if [[ -f "$SCRIPT_DIR/README.run.md" ]]; then
        cp "$SCRIPT_DIR/README.run.md" "$BUILD_DIR/README.md"
    fi
    info "Copied run.sh and README.md into archive"
}

package_archive() {
    step "13/13" "Packaging archive"

    # Preserve build logs in the archive
    mkdir -p "$BUILD_DIR/logs"
    cp "$BUILD_TMP"/*.log "$BUILD_DIR/logs/" 2>/dev/null || true
    rm -rf "$BUILD_TMP"

    local archive_name="patternfly_tools_${TARGET_PLATFORM}.zip"
    local archive_path="$SCRIPT_DIR/$archive_name"
    local parent_dir
    parent_dir="$(dirname "$BUILD_DIR")"

    info "Creating $archive_name..."

    (cd "$parent_dir" && zip -r "$archive_path" "$(basename "$BUILD_DIR")/") > /dev/null 2>&1 \
        || die "Failed to create zip archive"

    local size
    size=$(du -sh "$archive_path" | cut -f1)

    printf "\n"
    info "Archive created: $archive_path ($size)"
}

# ── Main ─────────────────────────────────────────────────────────────────
main() {
    printf "\n${BOLD}PatternFly Tools Builder${NC}\n"
    printf "========================\n\n"

    check_build_prerequisites
    detect_host_platform
    select_platform
    select_kantra_release

    BUILD_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/pf-build.XXXXXX")
    BUILD_DIR="$BUILD_ROOT/patternfly-tools"
    BUILD_TMP="$BUILD_ROOT/tmp"

    mkdir -p "$BUILD_DIR" "$BUILD_TMP"

    info "Build directory: $BUILD_ROOT"
    info "Build logs: $BUILD_TMP/*.log"

    download_kantra
    build_kantra_from_source
    build_java_external_provider
    build_semver_analyzer
    build_host_semver_analyzer
    build_frontend_analyzer_provider
    download_token_mappings
    generate_prepackaged_rules
    copy_prompt
    generate_manifest
    copy_run_script
    package_archive

    printf "\n"
    info "Build complete!"
    info "Archive: $SCRIPT_DIR/patternfly_tools_${TARGET_PLATFORM}.zip"
}

main
