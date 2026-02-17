# Ralph PRD Converter

Convert the PRD markdown file to `prd.json` format for the Ralph autonomous agent loop.

## The Job

Read the PRD markdown file provided and convert it to `prd.json`.

## Output Format

Write `prd.json` with this structure:

```json
{
  "project": "[Project Name]",
  "branchName": "ralph/[feature-name-kebab-case]",
  "description": "[Feature description from PRD title/intro]",
  "userStories": [
    {
      "id": "US-001",
      "title": "[Story title]",
      "description": "As a [user], I want [feature] so that [benefit]",
      "acceptanceCriteria": [
        "Criterion 1",
        "Criterion 2"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

## Story Size: The Number One Rule

Each story must be completable in ONE Ralph iteration (one context window).

**Right-sized stories:**
- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new logic
- Add a filter dropdown to a list

**Too big (split these):**
- "Build the entire dashboard" → Split into schema, queries, UI components, filters
- "Add authentication" → Split into schema, middleware, login UI, session handling

**Rule of thumb:** If you cannot describe the change in 2-3 sentences, it is too big.

## Story Ordering: Dependencies First

Stories execute in priority order. Earlier stories must not depend on later ones.

**Correct order:**
1. Schema/database changes (migrations)
2. Server actions / backend logic
3. UI components that use the backend
4. Dashboard/summary views that aggregate data

## Acceptance Criteria: Must Be Verifiable

Good: "Add `status` column to tasks table with default 'pending'"
Bad: "Works correctly"

Always include quality checks (typecheck/lint/tests pass) as final criteria.

## Conversion Rules

1. Each user story becomes one JSON entry
2. IDs: Sequential (US-001, US-002, etc.)
3. Priority: Based on dependency order, then document order
4. All stories: `passes: false` and empty `notes`
5. branchName: Derive from feature name, kebab-case, prefixed with `ralph/`

## Archiving

If a `prd.json` already exists with a different `branchName`, archive it first:
1. Create `archive/YYYY-MM-DD-feature-name/`
2. Copy `prd.json` and `progress.txt` to archive
3. Then write the new `prd.json`
