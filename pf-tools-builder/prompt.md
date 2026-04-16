This application has been migrated from PatternFly 5 to PatternFly 6 using automated tools. Pattern-based and LLM-assisted fixes have already been applied. Your job is to get the application into a building and working state.

## Step 1: Build

Run the application's build command. Identify all compilation and type errors.

## Step 2: Fix build errors

Fix each build error. Common issues after automated migration:
- Missing or incorrect imports
- Type mismatches from renamed interfaces or changed signatures
- Removed props still being used
- Changed component composition patterns (e.g., children vs slots)

When fixing errors, consult the PatternFly 6 API docs if needed:
- https://www.patternfly.org/get-started/upgrade/

Do not guess at fixes. If a component API has changed and you are unsure of the correct replacement, look it up.

## Step 3: Fix tests

After the build succeeds, run the test suite. Fix any test failures caused by the migration. Tests may fail due to:
- Changed component output or structure
- Updated CSS class names in snapshots
- Modified prop APIs in test assertions

Update snapshots if the new output is correct.

## Important

- Do not refactor, improve, or add features. Only fix what is broken.
- Do not add comments or documentation changes.
- Do not modify code that already builds and passes tests.
- Make minimal, targeted fixes.
