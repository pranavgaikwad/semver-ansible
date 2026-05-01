# Keeping scripts and roles in sync

When changing CLI flags, tool invocations, or behavior in any of these files, ensure the same change is reflected in all affected counterparts:

- `dist/run.sh` — standalone migration runner
- `dist/eval.sh` — standalone evaluation runner
- `dist/build.sh` — archive builder (embeds run.sh, prompt.md into the archive)
- `dist/run_container.sh` — container orchestration (passes flags to run.sh and eval.sh)
- `dist/Containerfile` — container image (COPYs run.sh, eval.sh, prompt.md)
- `ansible/roles/apply_fixes/tasks/main.yml` — ansible role that invokes fix-engine-cli
- `ansible/roles/semver_analysis/tasks/main.yml` — ansible role that invokes semver-analyzer
- `ansible/roles/kantra_analysis/tasks/main.yml` — ansible role that invokes kantra
