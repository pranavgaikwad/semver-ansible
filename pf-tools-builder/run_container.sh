#!/usr/bin/env bash
set -eo pipefail

# ── Colors ───────────────────────────────────────────────────────────────
if [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BOLD=''; NC=''
fi

info()  { printf "${GREEN}[INFO]${NC}  %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
die()   { error "$@"; exit 1; }

# ── Defaults ─────────────────────────────────────────────────────────────
DEFAULT_IMAGE="localhost/semver-runner:latest"
CONTAINER_WORKSPACE="/workspace"

MODE="mount"
IMAGE="$DEFAULT_IMAGE"
GOOSE_CONFIG=""
APP_PATH=""
PASSTHROUGH_ARGS=()

# ── Usage ────────────────────────────────────────────────────────────────
usage() {
    cat <<'EOF'
PatternFly Migration Tools — Container Runner

Usage: ./run_container.sh --migrate <PATH> [OPTIONS] [-- RUN.SH OPTIONS]

Container options:
  --migrate <PATH>           Project to migrate (required)
  --bake                     Bake app into image instead of mounting (for slow mounts)
  --goose-config <PATH>      Goose config directory (default: ~/.config/goose)
  --image <NAME>             Container image (default: localhost/semver-runner:latest)
  --enable-eval              Run evaluation agent after migration
  -h, --help                 Show help

All other options are forwarded to run.sh inside the container.
Examples: --agent claude, --rules-dir /path, --non-interactive
EOF
    exit 0
}

# ── Container runtime detection ──────────────────────────────────────────
detect_runtime() {
    if command -v podman >/dev/null 2>&1; then
        echo "podman"
    elif command -v docker >/dev/null 2>&1; then
        echo "docker"
    else
        die "Neither podman nor docker found. Install one to run the container."
    fi
}

# ── Argument parsing ─────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --migrate)        APP_PATH="$2"; shift 2 ;;
        --bake)           MODE="bake"; shift ;;
        --goose-config)   GOOSE_CONFIG="$2"; shift 2 ;;
        --image)          IMAGE="$2"; shift 2 ;;
        --enable-eval)    PASSTHROUGH_ARGS+=("--enable-eval"); shift ;;
        -h|--help)        usage ;;
        --)               shift; PASSTHROUGH_ARGS+=("$@"); break ;;
        *)                PASSTHROUGH_ARGS+=("$1"); shift ;;
    esac
done

# ── Validation ───────────────────────────────────────────────────────────
[[ -z "$APP_PATH" ]] && die "Missing required --migrate <PATH>"
[[ -d "$APP_PATH" ]] || die "Not a directory: $APP_PATH"
APP_PATH="$(cd "$APP_PATH" && pwd)"

[[ -z "${GCP_PROJECT_ID:-}" ]] && die "GCP_PROJECT_ID is not set. Export it before running (e.g., export GCP_PROJECT_ID=my-project)"
[[ -z "${GCP_LOCATION:-}" ]] && die "GCP_LOCATION is not set. Export it before running (e.g., export GCP_LOCATION=us-east5)"

RUNTIME=$(detect_runtime)
info "Container runtime: $RUNTIME"
info "Mode: $MODE"
info "Image: $IMAGE"
info "App: $APP_PATH"

# ── Goose config ─────────────────────────────────────────────────────────
MOUNT_ARGS=()
if [[ -n "$GOOSE_CONFIG" ]]; then
    if [[ -d "$GOOSE_CONFIG" ]]; then
        MOUNT_ARGS+=(-v "$GOOSE_CONFIG:/root/.config/goose:z")
        info "Goose config: $GOOSE_CONFIG (mounted)"
    else
        die "Goose config directory not found: $GOOSE_CONFIG"
    fi
else
    info "Goose config: using default (baked into image)"
fi

# ── GCP credentials ─────────────────────────────────────────────────────
GCP_CREDS_DIR="$HOME/.config/gcloud"
if [[ -d "$GCP_CREDS_DIR" ]]; then
    MOUNT_ARGS+=(-v "$GCP_CREDS_DIR:/root/.config/gcloud:ro,z")
    info "GCP credentials: $GCP_CREDS_DIR"
fi

# ── Environment variable passthrough ─────────────────────────────────────
ENV_ARGS=()
for var in GOOSE_PROVIDER GOOSE_MODEL GOOSE_API_KEY \
           ANTHROPIC_API_KEY OPENAI_API_KEY \
           GCP_PROJECT_ID GCP_LOCATION; do
    if [[ -n "${!var:-}" ]]; then
        ENV_ARGS+=(-e "$var")
    fi
done

# Point GOOGLE_APPLICATION_CREDENTIALS to the mounted path inside the container
if [[ -d "$GCP_CREDS_DIR" ]]; then
    ENV_ARGS+=(-e "GOOGLE_APPLICATION_CREDENTIALS=/root/.config/gcloud/application_default_credentials.json")
fi

# ── Paths inside container ────────────────────────────────────────────────
CONTAINER_LOGS="/mnt/logs"
LOGS_DEST="$PWD/.pf-migration-logs"

# ── Mode: Mount ──────────────────────────────────────────────────────────
run_mount_mode() {
    info "Mounting $APP_PATH at $CONTAINER_WORKSPACE"

    mkdir -p "$LOGS_DEST"

    local container_id
    container_id=$("$RUNTIME" run -d \
        -v "$APP_PATH:$CONTAINER_WORKSPACE:z" \
        -v "$LOGS_DEST:$CONTAINER_LOGS:z" \
        -e "LOGS_DIR=$CONTAINER_LOGS" \
        "${MOUNT_ARGS[@]}" \
        "${ENV_ARGS[@]}" \
        "$IMAGE" \
        --migrate "$CONTAINER_WORKSPACE" \
        --non-interactive \
        "${PASSTHROUGH_ARGS[@]}")

    info "Container: $container_id"
    "$RUNTIME" logs -f "$container_id" || true
    "$RUNTIME" wait "$container_id" > /dev/null 2>&1 || true

    "$RUNTIME" rm "$container_id" > /dev/null 2>&1 || true

    info "Results in: $APP_PATH"
    info "Logs in: $LOGS_DEST/"
}

# ── Mode: Bake ───────────────────────────────────────────────────────────
run_bake_mode() {
    local bake_tag="pf-baked-$(date +%s)"
    local temp_containerfile
    temp_containerfile=$(mktemp /tmp/pf-bake-XXXXXX)
    trap "rm -f '$temp_containerfile'" EXIT

    cat > "$temp_containerfile" <<EOF
FROM $IMAGE
COPY . $CONTAINER_WORKSPACE
RUN rm -f $CONTAINER_WORKSPACE/.git/index.lock
EOF

    info "Building baked image: $bake_tag"
    "$RUNTIME" build -t "$bake_tag" -f "$temp_containerfile" "$APP_PATH" \
        || die "Failed to build baked image"

    info "Running migration in baked image"
    local container_id
    container_id=$("$RUNTIME" run -d \
        "${MOUNT_ARGS[@]}" \
        "${ENV_ARGS[@]}" \
        "$bake_tag" \
        --migrate "$CONTAINER_WORKSPACE" \
        --non-interactive \
        "${PASSTHROUGH_ARGS[@]}")

    info "Container: $container_id"
    "$RUNTIME" logs -f "$container_id" || true
    "$RUNTIME" wait "$container_id" > /dev/null 2>&1 || true

    info "Syncing results from container"
    "$RUNTIME" cp "$container_id:$CONTAINER_WORKSPACE/." "$APP_PATH/"

    mkdir -p "$LOGS_DEST"
    "$RUNTIME" cp "$container_id:/opt/patternfly-tools/logs/." "$LOGS_DEST/" 2>/dev/null || true

    info "Cleaning up"
    "$RUNTIME" rm "$container_id" > /dev/null 2>&1 || true
    "$RUNTIME" rmi "$bake_tag" > /dev/null 2>&1 || true

    info "Results in: $APP_PATH"
    info "Logs in: $LOGS_DEST/"
}

# ── Main ─────────────────────────────────────────────────────────────────
case "$MODE" in
    mount) run_mount_mode ;;
    bake)  run_bake_mode ;;
    *)     die "Unknown mode: $MODE" ;;
esac
