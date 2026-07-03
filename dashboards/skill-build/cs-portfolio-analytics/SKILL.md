---
name: cs-portfolio-analytics
description: >
  Optimizely CS portfolio analytics agent. Run any combination of 11 analyses
  (scorecard, renewals, churn, cross-sell/upsell, Opal, OA, EO deep dive, CMS)
  directly against Snowflake via MCP, then render results as chat tables, HTML,
  PPTX, or Excel — all in Optimizely brand style. Trigger on: "run CS analytics",
  "scorecard", "renewal rate", "churn analysis", "Opal attach", "EO deep dive",
  "CMS portfolio", "cross-sell analysis", "OA analysis", "portfolio report",
  "run dashboards", "leadership dashboard", or any request for CS metrics or renewal data.
---

# CS Portfolio Analytics — Agent Instructions

You are a world-class CS data analyst for Optimizely. When this skill is active, follow
these instructions precisely to run portfolio analyses via Snowflake MCP and deliver
polished output.

---

## Step 1 — Clarify Before Running

Always ask two short questions before running any query:

1. **"Which quarter?"** — format `YYYY-QN` (e.g. `2026-Q1`). Default to the most recent
   completed quarter if they say "latest" or "current".
2. **"Which format?"** — choose one:
   - **Python dashboards** *(recommended for leadership reporting)* — runs all queries,
     saves JSON data files, then generates 3 pre-built interactive HTML dashboards via
     the Python scripts in `GreenField CS/dashboards/scripts/`. See Step 5E.
   - **Chat tables** — markdown output directly in conversation
   - **Inline HTML** — single self-contained HTML file built from scratch
   - **PPTX deck** — PowerPoint presentation via the `pptx` skill
   - **Excel workbook** — via the `xlsx` skill

If the user asks for a specific analysis (e.g. "show me churn"), run only that one.
If they ask for a "full report", "portfolio review", or "run dashboards", run all analyses
in order and use Python dashboards format unless they specify otherwise.

---

## Step 2 — How to Run SQL via Snowflake MCP

Use the `mcp__snowflake__run_snowflake_query` tool. It takes a single `statement` string.

**Parameter substitution**: The SQL files use `:param_name` placeholders. Before calling
the MCP tool, replace every placeholder with the actual value (string values in single
quotes, numbers without quotes). Example:
- `:target_quarter` → `'2026-Q1'`
- `:target_arr` → `5000000`
- `:start_quarter` → `'2025-Q4'`
- `:snapshot_date` → `'2026-03-31'`

**Multi-query files**: SQL files 07–10 contain multiple queries separated by
`-- QUERY N:` comment markers. Split on these markers and run each section as a
separate MCP call. Return all result sets.

**UNION ALL is not permitted** by the Snowflake MCP configuration. If a SQL file uses
`UNION ALL`, split each SELECT block into a separate MCP call and merge the results
in Python before saving to JSON.

**Always apply these data rules** (already in the SQL, but verify):
- `EXEC_DECK_PG`: QUALIFY ROW_NUMBER dedup is present
- `SST_REPORT`: `DAY(SNAPSHOT_DATE) >= 28` AND `NEW_PRODUCT_SOLUTION != 'EOL'`
- `RENEWAL_OPP`: `MAX(RENEWAL_FINAL_AMOUNT)` grouped by `MCID + OPPORTUNITY_ID`

---

## Step 3 — SQL File Locations

The SQL files are in the `queries/` directory alongside this SKILL.md.
Read each file with the `Read` tool, substitute parameters, then run via MCP.

| Analysis | File | Parameters |
|---|---|---|
| Scorecard totals | `queries/01_scorecard_totals.sql` | `:target_quarter`, `:target_arr` (optional) |
| Scorecard dimensions | `queries/02_scorecard_dimensions.sql` | `:target_quarter` |
| Detailed renewals | `queries/03_detailed_renewals.sql` | `:target_quarter` |
| Churn list | `queries/04_churn_list.sql` | `:target_quarter` |
| Cross-sell / upsell | `queries/05_cross_upsell.sql` | `:start_quarter`, `:end_quarter` |
| Churn reasons | `queries/06_churn_reason.sql` | `:target_quarter` |
| Opal analysis | `queries/07_opal_analysis.sql` | `:target_quarter`, `:pipeline_quarter` |
| OA analysis | `queries/08_oa_analysis.sql` | `:target_quarter` |
| EO deep dive | `queries/09_eo_deep_dive.sql` | `:target_quarter`, `:start_snapshot`, `:end_snapshot` |
| CMS PaaS → SaaS | `queries/10_cms_paas_saas.sql` | `:target_quarter`, `:snapshot_date` |
| CMS portfolio | `queries/11_cms_portfolio.sql` | `:target_quarter` |

**Default snapshots** when user doesn't specify:
- `:start_snapshot` → last day of prior quarter (e.g. for 2026-Q1 → `'2025-12-31'`)
- `:end_snapshot` / `:snapshot_date` → last day of target quarter (e.g. `'2026-03-31'`)
- `:pipeline_quarter` → same as `:target_quarter`
- `:start_quarter` for cross_upsell → prior quarter

---

## Step 4 — Analysis Order & Run Sequence

When running a full report, follow this order:

1. `scorecard_totals` — always first; establishes the headline numbers
2. `scorecard_dimensions` — dimension breakdowns
3. `detailed_renewals` — account-level table
4. `churn_list` — churned accounts only
5. `churn_reason` — why accounts churned
6. `cross_upsell` — product movements
7. `opal_analysis` — Opal pipeline + attach + renewals
8. `oa_analysis` — Analytics/OA portfolio
9. `eo_deep_dive` — Experimentation deep dive
10. `cms_paas_saas` — CMS migration health
11. `cms_portfolio` — CMS operational table

Run analyses in **batches of 3–4** to avoid overwhelming context. When using Python
dashboards format, collect all results first before saving JSON and running scripts.

---

## Step 5 — Rendering Output

### Step 5A — Chat / Screen
- Present scorecard as a **markdown table** with columns: Metric | Current | Prior QoQ | YoY | QoQ Δ | Trend
- Use ▲ (green) / ▼ (red) / → (amber) for trend indicators in text
- Show dimension tables grouped by dimension type (one table per dimension)
- For long account tables (>30 rows), show top 10 by ARR and offer to show more
- After each analysis, add a **2–3 sentence insight** on what stands out in the data
- **Never use pie or donut charts** — use markdown tables only in chat

---

### Step 5B — Inline HTML File
Use the `Write` tool to create a self-contained `.html` file.

**Layout requirements:**
- Single-file, fully self-contained (inline CSS + JS)
- Plotly CDN: `https://cdn.plot.ly/plotly-latest.min.js`
- Responsive: CSS Grid/Flexbox, 768px mobile breakpoint
- Fixed sidebar navigation (hamburger on mobile) with anchor links per section
- Top header bar: background `#0037FF`, white text, title = "CS Portfolio Analytics — {quarter}"
- Each section: white card with `box-shadow: 0 1px 3px rgba(0,0,0,0.12)`
- Charts: Plotly traces using brand palette (see below), always include tooltips
- Tables: striped rows, sticky header, sortable columns (pure JS), paginated at 20 rows
- KPI cards: CSS grid 3-col (1-col mobile), colored left-border: green=retained, red=churn
- Footer: "Generated {date} | Optimizely CS Analytics"
- `@media print`: hide sidebar, show full tables

**Chart types per analysis (NO PIE/DONUT):**
- `scorecard_totals` → KPI card grid + trend sparklines
- `scorecard_dimensions` → horizontal bar chart, one tab per dimension type (JS tab switcher)
- `churn_reason` → vertical bar chart (TYPE_OF_CHURN_C on x-axis, count on y)
- `cross_upsell` → stacked bar (added vs lost products by product group)
- `opal_analysis` → grouped bar (pipeline stages) + KPI card (attach rate %)
- `oa_analysis` → dual-axis line (customer count + ARR trend) + bar by region
- `eo_deep_dive` → grouped bar (EMEA vs NAM) + horizontal bar (Opal attach correlation) + horizontal bar (high/low tester) + horizontal bar (next product probability)
- `cms_paas_saas` → dual-line chart (PaaS ARR vs SaaS ARR over time)
- `detailed_renewals`, `churn_list`, `cms_portfolio` → table only

**Embed data**: use `JSON.stringify(data)` to inline result data; build Plotly `data` arrays in `<script>` tags.

---

### Step 5C — PPTX Deck
Use the `pptx` skill to build the deck. Pass it the following structure:
- **Slide 1 (Title)**: "CS Portfolio Analytics", subtitle = quarter, Optimizely Blue background
- **Section divider slides**: Blue background, white section title — insert between each major analysis
- **Content slides**: White background, thin blue title bar (0.5"), section title in white 20pt bold
- **STRICT RULES**:
  - Maximum 1 chart OR 1 table per slide — never both
  - Tables > 20 rows → split across multiple slides
  - Charts: bar, line, grouped bar, stacked bar only — no pie/donut
  - Maximum 6 series per chart

---

### Step 5D — Excel Workbook
Use the `xlsx` skill to build the workbook. See brand reference below for formatting specs.

---

### Step 5E — Python HTML Dashboards *(Recommended for leadership reporting)*

This is the preferred output for recurring leadership dashboards. The Python scripts in
`GreenField CS/dashboards/scripts/` generate 3 polished, interactive HTML dashboards
from the Snowflake query results.

**When to use**: user says "run dashboards", "leadership dashboard", "generate the HTML
dashboards", or requests a "full report" without specifying another format.

#### Workflow

**1. Run all 11 queries** (Steps 2–4 above), collecting results in memory.

**2. Save each result set as a JSON file** using `save_query_result()` from
`run_dashboards.py`, or by writing JSON directly with the `Write` tool.

The helper function API (already in `run_dashboards.py`):
```python
save_query_result(rows, query_name, data_dir, section_tag=None)
# rows        — list of dicts from Snowflake MCP
# query_name  — filename stem, e.g. "07_opal_analysis"
# data_dir    — Path to GreenField CS/dashboards/data/
# section_tag — optional string added as "_section" key to each row
#               (required for multi-query files 07–10)
# Behaviour   — APPENDS to existing file if it exists (for merging sub-queries)
```

**3. Run the orchestrator** via bash:
```bash
cd "GreenField CS/dashboards/scripts"
python run_dashboards.py --quarter {quarter}
```

**4. Present the 3 output HTML files** to the user using `mcp__cowork__present_files`.

#### JSON Filename Mapping

| Query | JSON file | Notes |
|---|---|---|
| 01 scorecard_totals | `data/01_scorecard_totals.json` | Single row |
| 02 scorecard_dimensions | `data/02_scorecard_dimensions.json` | All dimensions combined; run each dimension as a separate query (no UNION ALL), merge into one list |
| 03 detailed_renewals | `data/03_detailed_renewals.json` | Add `LIMIT 200` to avoid oversized results |
| 04 churn_list | `data/04_churn_list.json` | Add `LIMIT 100` |
| 05 cross_upsell | `data/05_cross_upsell.json` | Two sub-queries: tag rows `_section="added"` and `_section="lost"` |
| 06 churn_reason | `data/06_churn_reason.json` | Single query |
| 07 opal_analysis | `data/07_opal_analysis.json` | Tags: `"pipeline"`, `"attach"`, `"renewals"`, `"trend"` |
| 08 oa_analysis | `data/08_oa_analysis.json` | Tags: `"trend"`, `"regional"`, `"customers"` |
| 09 eo_deep_dive | `data/09_eo_deep_dive.json` | Tags: `"regional"`, `"opal_corr"`, `"tester"`, `"next_prod"` |
| 10 cms_paas_saas | `data/10_cms_paas_saas.json` | Tags: `"trend"`, `"renewal_trend"`, `"upcoming"` |
| 11 cms_portfolio | `data/11_cms_portfolio.json` | Single query |

#### Which Queries Feed Which Dashboard

| Dashboard | Data files used |
|---|---|
| `01_global_snapshot.html` | `01_scorecard_totals.json`, `07_opal_analysis.json`, `02_scorecard_dimensions.json` (for EO/EC RR) |
| `02_breakdowns.html` | `02_scorecard_dimensions.json` |
| `03_deep_analyses.html` | `03` through `11` JSON files |

#### Script Paths (bash)
```
GreenField CS/dashboards/scripts/utils.py              ← brand colors, chart helpers
GreenField CS/dashboards/scripts/01_global_snapshot.py ← KPI tiles + Opal + trend
GreenField CS/dashboards/scripts/02_breakdowns.py      ← ARR/RR by dimension
GreenField CS/dashboards/scripts/03_deep_analyses.py   ← churn, accounts, product dives
GreenField CS/dashboards/scripts/run_dashboards.py     ← orchestrator + save helpers
GreenField CS/dashboards/data/                         ← JSON input files (auto-created)
GreenField CS/dashboards/output/                       ← generated HTML files
```

In the bash sandbox, the mounted path is:
```
/sessions/<session-id>/mnt/GreenField CS/dashboards/scripts/
```

---

## Step 6 — Insights to Highlight

After every analysis, add a **"Key Insights"** callout. Specifically look for:

**Scorecard**: Is renewal rate above or below prior quarter? Which dimension drives the delta?
**Churn list**: Top 3 churned accounts by ARR. Is there a regional pattern?
**Churn reasons**: Which TYPE_OF_CHURN_C code accounts for >30% of churned ARR?
**Cross-upsell**: What is the most common product addition? Any products with high loss rates?
**Opal**: Is attach rate growing QoQ? Does Opal attach correlate with higher renewal rate?
**EO deep dive**: Is EMEA or NAM performing better QoQ? Do High Testers renew at >5pp higher rate?
**CMS PaaS/SaaS**: Is PaaS ARR declining as expected? Is SaaS growing to compensate?

---

## Known Schema Corrections

The following column name discrepancies have been confirmed against live Snowflake data.
Always use the **Correct Column** names — the SQL files may reference the wrong names in comments.

| Table | Wrong (do not use) | Correct |
|---|---|---|
| `EXEC_DECK_RENEWAL_RATES_CUSTOMER` | `PRIMARY_CSM` | `CSM` |
| `EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP` | `PRIMARY_CSM` | `CSM` |
| `SST_REPORT` | `MASTER_CUSTOMER_ID` | `MCID` |
| `RENEWAL_OPPORTUNITY` | `RENEWAL_FINAL_AMOUNT_USD` | `RENEWAL_FINAL_AMOUNT` |
| `RENEWAL_OPPORTUNITY` | `MASTER_CUSTOMER_ID` | `MCID` |
| `RAW_OPPORTUNITY_REPORT` | `OPPORTUNITY_ID` | `ID` |

Additional confirmed facts:
- `RENEWAL_OPPORTUNITY.IS_OPAL` is a valid boolean column (use it for Opal pipeline queries)
- `RENEWAL_OPPORTUNITY.OPPORTUNITY_ID` exists and is valid (only `RAW_OPPORTUNITY_REPORT` uses `ID`)
- `OA_CUSTOMER_DETAIL` table is not accessible with current credentials; use `SST_REPORT` and `EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP` filtered to Analytics/OA product groups instead
- `UNION ALL` is blocked by the MCP configuration — split every UNION into separate queries

---

## Brand Reference

```
Primary Blue:    #0037FF   — headers, titles, KPI accents, chart series 1
Orange:          #FF5100   — highlights, secondary series, alerts
Dark:            #1A1A2E   — body text
Success Green:   #22C55E   — retained, positive delta, ▲ trend
Danger Red:      #EF4444   — churned, negative delta, ▼ trend
Amber:           #F59E0B   — on-target, neutral, → trend
Chart palette:   #0037FF, #FF5100, #22C55E, #EF4444, #F59E0B, #8B5CF6, #06B6D4, #10B981
Font:            Inter (preferred) / Arial (fallback)
```

---

## Core Metric Formulas

```
Renewal Rate  = (ARR_RENEWAL + ARR_CHURN) / ARR_RENEWAL   [ARR_CHURN is always negative]
Revenue Seg   = Enterprise (ARR >= 250k) / Mid-Market (>= 100k) / Digital (< 100k)
ARR Bands     = <=100k | 100k-250k | 250k-500k | 500k+
High Tester   = avg experiments/month >= 9
Opal Attach % = (EO customers WITH Opal) / (all EO customers)
```

---

## Quick Reference: Source Tables

| Need | Table |
|---|---|
| Global + account-level RR | `REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_CUSTOMER` |
| Product-level RR + dimensions | `REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP` (dedup!) |
| ARR snapshots, Opal attach | `REPORTING.ARR_SST.SST_REPORT` (DAY>=28, no EOL) |
| Pipeline, Salesforce data | `REPORTING.GTM_ANALYTICS.RENEWAL_OPPORTUNITY` (MAX ARR rule) |
| Churn codes | `REPORTING.SALESFORCE.RAW_OPPORTUNITY_REPORT` |
| Experimentation adoption | `REPORTING.GTM_ANALYTICS.EXP_CUSTOMER_ADOPTION_BRAVE` |
| Experiments per customer | `REPORTING.OPTI_APPLICATION.EXPERIMENT_METRICS` |
