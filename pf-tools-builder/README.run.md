# PatternFly Migration Tools

Automated migration toolkit for upgrading applications from PatternFly 5 to PatternFly 6. Combines static analysis, pattern-based code fixes, LLM-assisted fixes, and an AI agent for remaining changes.

## Prerequisites

- **Java JDK** with `JAVA_HOME` set
- **AI agent** (one of): [Goose](https://github.com/block/goose), [Claude Code](https://docs.anthropic.com/en/docs/claude-code), or [OpenCode](https://github.com/opencode-ai/opencode)
- **yq** or **python3** (for YAML-to-JSON conversion)

For rule generation only:
- **git**
- **nvm** with Node.js 20.11.0

## Quick Start

```bash
cd patternfly-tools/
./run.sh --migrate /path/to/your/app
```

Or run interactively (prompts for options):

```bash
./run.sh
```

## Usage

```
./run.sh [OPTIONS]

Options:
  --migrate <PATH>           Migrate the project at PATH
  --generate-rules           Generate new PatternFly rules
  --agent <NAME>             Agent: goose (default), claude, opencode
  --rules-dir <PATH>         Custom rules directory
  --llm-timeout <SECS>       LLM timeout (default: 300)
  --from <REF>               --from for rule generation
  --to <REF>                 --to for rule generation
  --dep-from <REF>           --dep-from for rule generation
  --dep-to <REF>             --dep-to for rule generation
  --non-interactive          Skip all prompts
  -h, --help                 Show help
```

## Migration Pipeline

The migration runs in 8 steps:

| Step | Description |
|------|-------------|
| 1 | Generate provider settings |
| 2 | Start frontend-analyzer-provider |
| 3 | Run kantra static analysis |
| 4 | Stop frontend-analyzer-provider |
| 5 | Convert analysis output (YAML to JSON) |
| 6 | Apply pattern-based fixes |
| 7 | Apply LLM-based fixes (via goose) |
| 8 | Run AI agent for remaining fixes (optional, prompted) |

Steps 1-7 run automatically. Step 8 prompts for confirmation.

After step 7, all automated changes are committed with the message "Apply automated migration fixes (pattern-based + LLM)" so you can distinguish them from AI agent changes.

## Rule Generation

To generate rules from a different PatternFly version range:

```bash
./run.sh --generate-rules
```

This clones PatternFly repos, prompts for version tags, and generates rules. The output path is saved to `.semver_runner` in the current directory and will be offered on the next `--migrate` run.

Non-interactive:

```bash
./run.sh --generate-rules --from v5.4.0 --to v6.4.1 --dep-from v5.4.0 --dep-to v6.4.0 --non-interactive
```

## Using Custom Rules

```bash
./run.sh --migrate /path/to/app --rules-dir /path/to/rules
```

## Logs

Each run creates a timestamped log directory under `logs/`:

```
logs/20260416T140000/
├── kantra.log
├── fix-pattern.log
├── fix-llm.log
├── agent-goose.log    # or agent-claude.log / agent-opencode.log
├── semver_analyze.log # only for --generate-rules
└── semver_konveyor.log
```

## Archive Contents

```
patternfly-tools/
├── .kantra/           # Kantra binary and assets
├── bin/               # semver-analyzer, frontend-analyzer-provider, fix-engine-cli
├── rules/             # Pre-generated migration rules and fix strategies
├── prompt.md          # AI agent prompt
├── MANIFEST           # Build metadata (git SHAs, rule count, versions)
├── run.sh             # This runner
└── README.md          # This file
```
