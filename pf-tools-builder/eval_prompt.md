You are an expert software migration reviewer. Your task is to compare one or more git branches that all attempt to migrate the same application from PatternFly 5 to PatternFly 6, and determine which branch performs the migration most fully and correctly. You will create an interactive HTML report documenting your findings.

# High-level goal

Determine which branch is the best PatternFly 5 → 6 migration.

The winner is the branch that:
1. Completes more of the required PatternFly migration work,
2. Preserves the original application behavior more faithfully,
3. Minimizes unnecessary changes unrelated to the PatternFly upgrade,
4. Builds more successfully with fewer errors,

The migration target is specifically PatternFly 6. Your evaluation must stay tightly focused on the PatternFly dependency upgrade. Do not reward unrelated refactors, feature additions, stylistic rewrites, or architectural churn unless they are clearly necessary for the PatternFly migration.

### Inputs

The arguments are: `$ARGUMENTS`

Parse them as follows:
- The **first** argument is the base (pre-migration) branch.
- Every subsequent argument is a migration branch to evaluate.
- There may be 1, 2, 3, or more migration branches. Adapt all analysis, tables, grids, and scoring to the actual number of branches provided.

If only one migration branch is provided, the report becomes an absolute assessment of that branch's migration quality rather than a comparison. Skip winner/loser language; instead score the branch out of 10 and provide a "ship or fix" recommendation.

## Phase 1: Independent research FIRST
Before comparing the branches, do your own research.

You must use Web Search extensively and prefer official / primary sources whenever possible, especially:
- Official PatternFly upgrade guides
- Official PatternFly release notes / breaking changes
- Official PatternFly React package documentation

Here are some links to get started with: 
- https://www.patternfly.org/get-started/upgrade/ (follow links for different topics in  this doc)

Research the latest available guidance for migrating from PatternFly 5 to PatternFly 6. Build an explicit migration checklist from your research before looking at the branches in detail.

Do not assume prior knowledge is sufficient. Confirm with current web research. Use sub-agents and web search liberally to achieve this.

## Phase 2: Establish comparison baseline

The first argument is the base branch.

Before scoring any migration branch, identify for **each** migration branch:
- diff from base → migration branch
- The net PatternFly-related changes
- Any major unrelated changes

Create a “migration checklist” from Phase 1 and use that checklist consistently against all branches. Use sub-agents in parallel to gather this information — one agent per branch for diffs, plus one for building each branch.

## Phase 3: Branch-by-branch analysis

Analyze each branch systematically and independently first. Do not decide the winner too early.

For each branch, evaluate the following categories:

### 1. Migration completeness
Check whether the branch addresses all major areas required for a PatternFly 5 → 6 migration.

Examples of things to verify include, where applicable:
- Package upgrades to the correct PatternFly 6 packages/versions
- Related PatternFly package alignment
- Remaining TODOs / warnings / broken imports
- Renamed, replaced, or removed components
- API / prop changes
- Chart import path changes
- Styling / token / class / theme migration needs
- Empty state and other components that require manual changes
- Any missed migration hotspots revealed by official docs

You must explicitly identify:
- completed migration areas
- partially completed areas
- missed areas

### 2. Functional preservation
The purpose is to upgrade PatternFly, not to change product behavior.

Check whether the original functionality is preserved:
- Same user-facing workflows
- Same business behavior
- Same control flow and interaction semantics
- Same routing and navigation behavior
- Same form behavior
- Same validation behavior

Distinguish clearly between:
- legitimate UI-library migration changes
- accidental behavior changes
- feature additions
- feature removals
- refactors that alter behavior without need

Any unnecessary behavior change counts against the branch.

### 3. Scope discipline / minimality of change
Prefer the branch that changes only what is necessary for the PatternFly upgrade.

Penalize:
- unrelated refactors
- renamed files/functions without migration need
- logic rewrites not required by PatternFly 6
- feature additions
- broad dependency churn not justified by the migration

Reward:
- focused diffs
- precise migration edits
- clear upgrade-specific changes
- minimal collateral damage

### 4. Correctness of PatternFly-specific migration
Evaluate whether the migration appears semantically correct for PatternFly 6, not just syntactically changed.

Check for things such as:
- use of the right replacement components
- prop changes applied correctly
- old APIs fully removed
- imports updated correctly
- charts updated correctly if PatternFly charts are used
- tokens / CSS variables / class names updated appropriately
- component composition adjusted correctly where required
- compatibility with official migration guidance
- no leftover PatternFly 5 usage patterns that will cause runtime, visual, or maintenance issues

### 5. Build / compile / testability
Attempt to build each branch.

At minimum:
- install dependencies if needed
- run the appropriate build / compile command(s)
- capture compile / type / lint errors if they block build
- identify PatternFly-related build failures separately from unrelated pre-existing failures where possible

If practical, also run relevant tests. But build / compile validation is mandatory.

For each branch, report:
- whether it builds successfully
- exact error categories if it fails
- whether failures are directly caused by incomplete migration
- whether failures are easy or hard to fix

### 6. Risk / maintainability
Assess future risk introduced by the migration:
- leftover deprecated patterns
- partial migration that will cause future breakage
- brittle workaround code
- missing follow-through after codemod output
- theming/styling inconsistencies
- divergence from official upgrade path

If you discover additional important PatternFly-6-specific criteria during research, add them explicitly to the evaluation.

# Scoring rules

Score all migration branches across the categories above.

For each major area and sub-area:
- declare a clear winner (by display title) or Tie
- explain why
- assign points

Scoring requirements:
- A winner gets full points for that area
- In a tie, both branches get equal points
- If an area has sub-areas, score them individually and also summarize at the area level
- Use consistent point weights
- Be explicit and auditable

# Evidence standards

Your findings must be evidence-driven.

For every important conclusion:
- cite concrete code evidence from the branches
- cite specific build outputs where relevant
- cite web research sources where relevant
- distinguish facts from inferences
- clearly label uncertainty

Do not make vague claims like “seems better” or “probably more complete” without evidence.

# Important judgment rules

1. The goal is not “which branch changed more”.
   The goal is “which branch completed the PatternFly 6 migration better with minimal unnecessary change”.

2. Do not reward branches for adding new features.

3. Do not reward broad refactors unless they are clearly required for PatternFly 6.

4. A branch that builds but leaves significant migration gaps should not automatically win.

5. A branch that is more complete but introduces unnecessary behavioral changes should be penalized.

6. If one branch is cleaner but the other is more complete, explain the tradeoff explicitly and let the score reflect it.

7. Treat official PatternFly documentation and release guidance as authoritative.


Your final output must be an interactive HTML report saved to `pf-migration-comparison-report.html` in the project root.

# Report Format Specification

The report MUST follow this exact structure, styling, and HTML/CSS template. Consistency across runs is critical.

## Report sections (in order)

### 1. Final verdict banner
- Green-bordered card at the top with gradient background
- If multiple branches: shows “Winner: Branch X” in large green text
- If single branch: shows “Assessment: Branch X — N / 10” with green (≥8), orange (5-7), or red (<5)
- One score card per migration branch, side by side in a flex row
- Winner card has green border; worst score gets red; others get orange
- 3-7 bullet points summarizing decisive reasons

### 2. Table of Contents
- Numbered, linked list inside a bordered card
- Links to all major sections

### 3. Branch Overview & Stats
- One card per migration branch, side by side (use CSS grid; set `grid-template-columns: repeat(N, 1fr)` where N = number of migration branches, capped at 4 columns — wrap to next row if more)
- Winner card gets class `best` (green border)
- Each card shows: branch name, commit count, files changed, insertions, deletions, package.json updated (Yes/No), CSS/SCSS updated (Yes/No), build result, remaining pf-v5 references
- Use metric rows with label on left, value on right
- Color values: green for good, red for bad, orange for warnings

### 4. Build Error Comparison
- Horizontal bar chart showing error count per branch
- Red bar for most errors, orange for medium, green for fewest

### 5. Side-by-Side Scoring Tables
- Summary table: Category | Max | one column per migration branch | Winner
- Bold total row at bottom
- Detailed breakdown table: Area | Sub-area | one “findings” column per migration branch | Winner | Evidence
- Use rowspan for area grouping
- Winner cells get class `winner-cell` (green), losers get `loser-cell` (red), ties get `tie-cell` (orange)
- Winner badges: `<span class=”badge badge-green”>BranchName</span>`, ties: `badge-orange`, special wins: `badge-blue`

### 6. Detailed discussion sections (one per migration area)
Each area gets its own `<h2>` with an id for linking. Within each area, use collapsible `<details>` elements (first one open):
- `<summary>` = area name
- Inside `.content` div:
  - Brief explanation of what changed in PF6 with link to official docs
  - PF5 “Before” code block in `<pre><code>`
  - PF6 “After” code block in `<pre><code>`
  - Small comparison table with one row per migration branch: Branch | Status | Notes
  - Winner badge and explanation (or just assessment badge if single branch)

Areas to cover (each as a separate `<details>`):
- Package version upgrades (always include full table of all PF packages)
- Text/Content migration
- EmptyState restructuring
- Tile → Card
- Modal migration
- DataListItemCells removal
- InputGroupItem / DescriptionListGroup
- PageSection variant
- ExpandableSection onToggle
- Dropdown/Select onSelect
- Button icon prop
- Flex spaceItems → gap
- FormGroup labelIcon → labelHelp
- Nav theme removal
- Label color changes
- Tabs eventKey type
- Charts import path
- CSS class prefix migration (with bar chart of remaining pf-v5 refs)
- React token imports (with table mapping old → new per branch)
- CSS variable tokens (spacers, colors, backgrounds, borders, fonts, breakpoints)
- Scope discipline / unrelated changes

### 7. Build Results section
- Per-branch subsection with badge (green/orange/red)
- Error summary table: Error Type | Count | Root Cause
- For the passing branch, list warnings and note they are pre-existing
- Build summary progress bar at bottom

### 8. Risk & Maintainability
- One card per migration branch, same grid as overview
- Metrics: placeholder tokens, stale CSS classes, package alignment, missing deps, runtime risk, manual work remaining
- List remaining migration gaps common to all branches

### 9. Final Totals & Recommendation
- Inside a verdict-styled card (green border, gradient background)
- Score table: Category (max) | one column per migration branch
- Bold total row with colored scores
- “Recommendation” section with bold merge recommendation
- “Remaining work” on winning branch
- For each non-winning branch: “If fixing [branch] instead” section with prioritized fix list

## CSS Theme (use exactly these variables and styles)

```css
:root {
  --bg: #0d1117;
  --surface: #161b22;
  --surface2: #1c2129;
  --border: #30363d;
  --text: #e6edf3;
  --text-muted: #8b949e;
  --accent: #58a6ff;
  --green: #3fb950;
  --red: #f85149;
  --orange: #d29922;
  --purple: #bc8cff;
  --teal: #39d2c0;
}
```

- Body: dark background (`--bg`), light text, max-width 1400px, 2rem padding
- Font: system font stack (-apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif)
- h1: 1.8rem, blue accent bottom border
- h2: 1.4rem, blue accent color, top margin 2rem, bottom border
- h3: 1.15rem, purple color
- h4: 1rem, teal color
- Tables: full width, collapsed borders, 0.85rem font, dark surface cells, sticky headers
- Code: dark surface2 background, orange text, 4px border-radius
- Pre blocks: surface2 background, 1rem padding, 8px radius, border

## CSS Component Classes

- `.verdict`: green border, gradient bg (#1a3a2a → #162b22), 12px radius, 1.5rem padding
- `.score-card`: surface bg, 8px radius, border. `.winner-card` gets green border
- `.compare-grid`: CSS grid, `repeat(N, 1fr)` columns where N = number of migration branches (cap at 4; wrap if more). Falls to 1 column under 900px
- `.compare-card`: surface bg, border, 8px radius. `.best` gets green border
- `.metric`: flex row, space-between, bottom border. `.good`=green, `.bad`=red, `.warn`=orange
- `.badge`: inline-block, 12px radius, 0.8rem font. Variants: `.badge-green`, `.badge-red`, `.badge-orange`, `.badge-blue` (each with matching 15% opacity bg + solid border)
- `.bar-chart` / `.bar-row` / `.bar-track` / `.bar-fill`: horizontal bar chart components
- `.progress-bar`: flex row, 24px height, 6px radius, segments with colors
- `details`: surface bg, border, 8px radius, overflow hidden. Summary has pointer cursor, hover bg. Open summary gets bottom border
- `.winner-cell`: green + bold. `.loser-cell`: red. `.tie-cell`: orange

## Visualization requirements

- Build errors: horizontal bar chart with one row per migration branch (percentage width relative to max errors)
- Remaining pf-v5 references: horizontal bar chart with one row per migration branch
- Build summary: segmented progress bar with one segment per migration branch
- Branch overview: N-column card grid with metrics (N = number of migration branches)
- Risk assessment: N-column card grid with metrics
- Scores: score cards in flex row, one per migration branch

## Footer

```html
<p style=”color: var(--text-muted); margin-top: 2rem; text-align: center; font-size: 0.85rem;”>
  Report generated by Claude Code migration analysis &bull; Sources:
  <a href=”https://www.patternfly.org/get-started/upgrade/”>PatternFly Upgrade Guide</a>,
  <a href=”https://www.patternfly.org/tokens/develop-with-tokens/”>PatternFly Tokens</a>,
  <a href=”https://www.patternfly.org/get-started/upgrade/release-notes/”>PF6 Release Notes</a>
</p>
```

# Quality bar

Your report should be rigorous enough that an engineering lead could use it to decide which branch to merge.

Be systematic, skeptical, and evidence-based.
Research first. Compare second. Build third. Conclude last.

