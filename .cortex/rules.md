# Project Rules

## SQL Style
- UPPERCASE all SQL keywords (SELECT, FROM, WHERE, JOIN, WITH, CASE, WHEN, THEN, END, etc.)
- UPPERCASE CTE names (e.g., `WITH onb_base AS (...)`)
- Use explicit short table aliases (e.g., `oc`, `dg`, `de`, `prod`, `a`, `t`)
- Inline comments for non-obvious logic (`-- floored at 0`, `-- Experimentation + Opal only`)
- One CTE per logical step; name CTEs descriptively

## Workflow
- Always show a clear plan before starting implementation
- Ask about data sources or data definitions — only search/query when user gives the go-ahead
- Minimal, targeted edits only — don't refactor surrounding code
- Offer simplification after 5 re-edits on the same section

## Architecture
- Base SQL + pandas for calculations (SQL fetches, Python transforms for complex aggregations)
- Standardized HTML visuals: filterable columns, CSV export buttons, Chart.js charts
- `render_html.py` section builders follow signature: `(analysis_id: str, frames: dict, js_buf: list) -> str`

## Domain
- Customer Success: onboarding, go-live, TTGL, retention, renewals, churn
- Sales: pipelines, bookings, ARR, product attach
- Cohorts: quarterly vintages, retention curves, eligibility-aware denominators
- Products: Experimentation, Opal, CMS (derived from REPORTING_CATEGORY_C)
