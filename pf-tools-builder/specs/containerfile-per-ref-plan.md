# Plan: Update Containerfile Stage 3 for Per-Ref Node Versions

## Context

The `run.sh` on this branch already supports `--from-node-version`, `--to-node-version`, and `--from-install-command` flags for rule generation. The Containerfile's Stage 3 (rule-generator) needs to match — it currently hardcodes `ubi9/nodejs-20` as the base and doesn't pass per-ref flags to `semver-analyzer analyze`.

The goal is to make Stage 3 parameterizable via `docker build --build-arg` so the image can be rebuilt with different PatternFly version combos and node versions without editing the Containerfile.

## Changes

### File: `Containerfile` — Stage 3 only (lines 73–114)

#### 1. Switch base image (line 74)

Replace:
```dockerfile
FROM registry.access.redhat.com/ubi9/nodejs-20 AS rule-generator
```
With:
```dockerfile
FROM registry.access.redhat.com/ubi9/ubi AS rule-generator
```

#### 2. Update ARG defaults (lines 75–79)

Update existing version defaults to match the user's target:
```dockerfile
ARG PF_REACT_FROM=v5.3.3
ARG PF_REACT_TO=v6.4.1
ARG PF_DEP_FROM=v5.3.0
ARG PF_DEP_TO=v6.4.0
```

Add new ARGs for per-ref build configuration:
```dockerfile
ARG FROM_NODE_VERSION=18
ARG TO_NODE_VERSION=20
ARG FROM_INSTALL_CMD="corepack yarn install"
```

#### 3. Replace system deps + node setup (lines 82–84)

Remove:
```dockerfile
USER root
RUN dnf install -y git && dnf clean all
RUN npm install -g corepack && corepack enable
```

Replace with:
```dockerfile
RUN dnf install -y git curl && dnf clean all

SHELL ["/bin/bash", "-c"]

ENV NVM_DIR=/root/.nvm
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash \
    && source "$NVM_DIR/nvm.sh" \
    && nvm install "$FROM_NODE_VERSION" \
    && nvm install "$TO_NODE_VERSION" \
    && nvm alias default "$TO_NODE_VERSION" \
    && npm install -g corepack && corepack enable
```

Notes:
- `SHELL ["/bin/bash", "-c"]` ensures nvm (a bash function) works in subsequent RUN commands
- Pre-install both node versions so semver-analyzer can switch between them
- corepack is installed under the default (TO) node version

#### 4. Update semver-analyzer analyze command (lines 97–106)

Add per-ref flags to the existing command:
```dockerfile
RUN source "$NVM_DIR/nvm.sh" && semver-analyzer analyze typescript \
    --repo /src/patternfly-react \
    --from "$PF_REACT_FROM" --to "$PF_REACT_TO" \
    --dep-repo /src/patternfly \
    --dep-from "$PF_DEP_FROM" --dep-to "$PF_DEP_TO" \
    --dep-build-command "yarn install && npx gulp buildPatternfly" \
    --build-command "corepack yarn build" \
    --from-node-version "$FROM_NODE_VERSION" \
    --to-node-version "$TO_NODE_VERSION" \
    --from-install-command "$FROM_INSTALL_CMD" \
    --no-llm \
    -o /src/semver_report.json
```

Key differences from current:
- Source nvm before running semver-analyzer
- Add `--from-node-version`, `--to-node-version`, `--from-install-command`
- `--dep-build-command` stays hardcoded (per discussion)
- `--build-command` stays hardcoded

#### 5. Reset SHELL for subsequent stages

After Stage 3, add:
```dockerfile
SHELL ["/bin/sh", "-c"]
```
before Stage 4 to restore the default shell for the runtime image.

## What does NOT change

- **Stages 1, 2, 4**: Untouched
- **`--dep-build-command`**: Stays hardcoded as `"yarn install && npx gulp buildPatternfly"`
- **`--build-command`**: Stays hardcoded as `"corepack yarn build"`
- **konveyor call** (lines 109–113): No per-ref flags needed (uses `--from-report`)
- **`run.sh`**: Already updated on this branch

## Verification

1. Build the image with defaults (v5.4.0 → v6.4.1, node 20/20):
   ```
   docker build -t pf-tools .
   ```
2. Build with v5.3.3 overrides (node 18 → 20):
   ```
   docker build \
     --build-arg PF_REACT_FROM=v5.3.3 \
     --build-arg PF_DEP_FROM=v5.3.0 \
     --build-arg FROM_NODE_VERSION=18 \
     --build-arg FROM_INSTALL_CMD="corepack yarn install" \
     -t pf-tools .
   ```
3. Verify the generated rules exist in the final image:
   ```
   docker run --rm pf-tools ls rules/semver_rules/
   ```
