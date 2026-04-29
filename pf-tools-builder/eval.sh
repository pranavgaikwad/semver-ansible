#!/usr/bin/env bash
set -eo pipefail

GLOBAL_START=$SECONDS
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colors ───────────────────────────────────────────────────────────────
if [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
fi

# ── Layout ───────────────────────────────────────────────────────────────
EVAL_PROMPT_FILE="$SCRIPT_DIR/eval_prompt.md"
LOGS_DIR="${LOGS_DIR:-$SCRIPT_DIR/logs/$(date -u +%Y%m%dT%H%M%S)}"

# ── Defaults ─────────────────────────────────────────────────────────────
MIGRATE_PATH=""
BASE_BRANCH="main"
MIGRATION_BRANCH=""
AGENT="goose"
NON_INTERACTIVE=false

# ── Utilities ────────────────────────────────────────────────────────────
info()  { printf "${GREEN}[INFO]${NC}  %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }
step()  { printf "\n${BLUE}[STEP %s]${NC} %s\n" "$1" "$2"; }
die()   { error "$@"; exit 1; }

require_file() {
    [[ -f "$1" ]] || die "Required file not found: $1"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

# ── Cleanup ──────────────────────────────────────────────────────────────
cleanup() {
    local exit_code=$?
    local total_elapsed=$(($SECONDS - GLOBAL_START))
    if [[ "$exit_code" -ne 0 ]]; then
        printf "\n" >&2
        error "Eval failed with exit code $exit_code (${total_elapsed}s)"
        error "Check logs in $LOGS_DIR/ for details"
    else
        info "Total eval runtime: $((total_elapsed/60))m$((total_elapsed%60))s"
    fi
    exit "$exit_code"
}
trap cleanup EXIT INT TERM

# ── Argument parsing ─────────────────────────────────────────────────────
usage() {
    cat <<'EOF'
PatternFly Migration Evaluation

Evaluates a migrated branch by comparing it against pf-codemods output and the base branch.

Usage: ./eval.sh --migrate <PATH> --branch <BRANCH> [OPTIONS]

Required:
  --migrate <PATH>           Path to the application
  --branch <BRANCH>          Migration branch to evaluate

Options:
  --base-branch <NAME>       Base branch (default: main)
  --agent <NAME>             Agent: goose (default), claude, opencode
  --non-interactive          Skip all prompts
  -h, --help                 Show help
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --migrate)         MIGRATE_PATH="$2"; shift 2 ;;
        --branch)          MIGRATION_BRANCH="$2"; shift 2 ;;
        --base-branch)     BASE_BRANCH="$2"; shift 2 ;;
        --agent)           AGENT="$2"; shift 2 ;;
        --non-interactive) NON_INTERACTIVE=true; shift ;;
        -h|--help)         usage ;;
        *)                 die "Unknown option: $1" ;;
    esac
done

[[ -z "$MIGRATE_PATH" ]] && die "Missing required --migrate <PATH>"
[[ -d "$MIGRATE_PATH" ]] || die "Not a directory: $MIGRATE_PATH"
MIGRATE_PATH="$(cd "$MIGRATE_PATH" && pwd)"
[[ -z "$MIGRATION_BRANCH" ]] && die "Missing required --branch <BRANCH>"

mkdir -p "$LOGS_DIR"

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/pf-eval.XXXXXX")

info "Project:    $MIGRATE_PATH"
info "Base:       $BASE_BRANCH"
info "Branch:     $MIGRATION_BRANCH"
info "Agent:      $AGENT"
info "Logs:       $LOGS_DIR/"

# ── Step 1: Run pf-codemods on a new branch ──────────────────────────────
step "1/3" "Running pf-codemods"

CODEMODS_BRANCH="pf-codemods-$(date -u +%m%d%y-%H%M)"
info "Creating pf-codemods branch: $CODEMODS_BRANCH"

(cd "$MIGRATE_PATH" \
    && git checkout "$BASE_BRANCH" \
    && git checkout -b "$CODEMODS_BRANCH") \
    || die "Failed to create pf-codemods branch from $BASE_BRANCH"

info "Running 'npx @patternfly/pf-codemods@latest $MIGRATE_PATH --v6 --fix'"
(cd "$MIGRATE_PATH" && npx @patternfly/pf-codemods@latest "$MIGRATE_PATH" --v6 --fix) \
    > "$LOGS_DIR/pf-codemods.log" 2>&1 || {
    warn "pf-codemods exited with non-zero status. Check $LOGS_DIR/pf-codemods.log"
}

# Commit codemods changes
(cd "$MIGRATE_PATH" && \
    git add -A && \
    git diff --cached --quiet || \
    git commit -m "Apply pf-codemods v6 migration") \
    > /dev/null 2>&1 || true
info "Committed pf-codemods changes on $CODEMODS_BRANCH"

# Switch back to migration branch for eval context
(cd "$MIGRATE_PATH" && git checkout "$MIGRATION_BRANCH") \
    || die "Failed to checkout migration branch $MIGRATION_BRANCH"

# ── Step 2: Run evaluation agent ─────────────────────────────────────────
step "2/3" "Running evaluation agent"

require_file "$EVAL_PROMPT_FILE"

EVAL_ARGS="$BASE_BRANCH $CODEMODS_BRANCH $MIGRATION_BRANCH"
eval_prompt=$(sed "s|\$ARGUMENTS|$EVAL_ARGS|g" "$EVAL_PROMPT_FILE")

eval_prompt_tmp="$TEMP_DIR/eval_prompt.md"
echo "$eval_prompt" > "$eval_prompt_tmp"

pushd "$MIGRATE_PATH" > /dev/null || die "Failed to cd into $MIGRATE_PATH"

info "Evaluating: $BASE_BRANCH → $CODEMODS_BRANCH vs $MIGRATION_BRANCH"
info "Follow logs: tail -f $LOGS_DIR/eval-agent.log"

case "$AGENT" in
    goose)
        require_command goose
        info "Running 'GOOSE_MODE=auto goose run -i $eval_prompt_tmp'"
        unbuffer env GOOSE_MODE=auto goose run -i "$eval_prompt_tmp" \
            > "$LOGS_DIR/eval-agent.log" 2>&1 || {
            warn "Evaluation agent exited with non-zero status. Check $LOGS_DIR/eval-agent.log"
        }
        ;;
    claude)
        require_command claude
        info "Running 'claude --allowedTools ... -p $eval_prompt_tmp'"
        unbuffer claude --allowedTools "Bash" "Edit" "Write" "Read" "WebSearch" "WebFetch" \
            -p "$(cat "$eval_prompt_tmp")" \
            > "$LOGS_DIR/eval-agent.log" 2>&1 || {
            warn "Evaluation agent exited with non-zero status. Check $LOGS_DIR/eval-agent.log"
        }
        ;;
    opencode)
        require_command opencode
        info "Running 'opencode run $eval_prompt_tmp'"
        unbuffer opencode run "$(cat "$eval_prompt_tmp")" \
            > "$LOGS_DIR/eval-agent.log" 2>&1 || {
            warn "Evaluation agent exited with non-zero status. Check $LOGS_DIR/eval-agent.log"
        }
        ;;
    *)
        die "Invalid agent: $AGENT. Must be goose, claude, or opencode"
        ;;
esac

popd > /dev/null

# Copy evaluation report to logs
if [[ -f "$MIGRATE_PATH/pf-migration-comparison-report.html" ]]; then
    cp "$MIGRATE_PATH/pf-migration-comparison-report.html" "$LOGS_DIR/"
    info "Evaluation report: $LOGS_DIR/pf-migration-comparison-report.html"
else
    warn "Evaluation report not found at $MIGRATE_PATH/pf-migration-comparison-report.html"
fi

# ── Step 3: Cleanup pf-codemods branch ───────────────────────────────────
step "3/3" "Cleaning up"

(cd "$MIGRATE_PATH" && git branch -D "$CODEMODS_BRANCH") \
    > /dev/null 2>&1 || warn "Failed to delete $CODEMODS_BRANCH"
info "Deleted pf-codemods branch: $CODEMODS_BRANCH"

printf "\n"
info "Evaluation complete!"
info "Project: $MIGRATE_PATH"
info "Logs: $LOGS_DIR/"
