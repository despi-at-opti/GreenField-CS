---
name: cs-portfolio-analytics
description: >
  Optimizely CS portfolio analytics agent. Run any combination of 11 analyses
  (scorecard, renewals, churn, cross-sell/upsell, Opal, OA, EO deep dive, CMS)
  directly against Snowflake via MCP, then render results as chat tables, HTML,
  PPTX, or Excel — all in Optimizely brand style. Trigger on: "run CS analytics",
  "scorecard", "renewal rate", "churn analysis", "Opal attach", "EO deep dive",
  "CMS portfolio", "cross-sell analysis", "OA analysis", "portfolio report",
  or any request for CS metrics or renewal data.
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
2. **"Which format?"** — chat tables, HTML file, PPTX deck, or Excel workbook.

If the user asks for a specific analysis (e.g. "show me churn"), run only that one.
If they ask for a "full report" or "portfolio review", run all analyses in order.

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

**Always apply these data rules** (already in the SQL, but verify):
- `EXEC_DECK_PG`: QUALIFY ROW_NUMBER dedup is present
- `SST_REPORT`: `DAY(SNAPSHOT_DATE) >= 28` AND `NEW_PRODUCT_SOLUTION != 'EOL'`
- `RENEWAL_OPP`: `MAX(RENEWAL_FINAL_AMOUNT_USD)` grouped by `MCID + OPPORTUNITY_ID`
- Never use `RENEWAL_OPP.IS_OPAL` — derive Opal attach from SST_REPORT or EXEC_DECK_PG

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

Run analyses in **batches of 3** to avoid overwhelming context. Present each batch before
proceeding to the next.

---

## Step 5 — Rendering Output

### Chat / Screen
- Present scorecard as a **markdown table** with columns: Metric | Current | Prior QoQ | YoY | QoQ Δ | Trend
- Use ▲ (green) / ▼ (red) / → (amber) for trend indicators in text
- Show dimension tables grouped by dimension type (one table per dimension)
- For long account tables (>30 rows), show top 10 by ARR and offer to show more
- After each analysis, add a **2–3 sentence insight** on what stands out in the data
- **Never use pie or donut charts** — use markdown tables only in chat

### HTML File
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

### PPTX Deck
Use the `pptx` skill to build the deck. Pass it the following structure:
- **Slide 1 (Title)**: "CS Portfolio Analytics", subtitle = quarter, Optimizely Blue background
- **Section divider slides**: Blue background, white section title — insert between each major analysis
- **Content slides**: White background, thin blue title bar (0.5"), section title in white 20pt bold
- **STRICT RULES**:
  - Maximum 1 chart OR 1 table per slide — never both
  - Tables > 20 rows → split across multiple slides
  - Charts: bar, line, grouped bar, stacked bar only — no pie/donut
  - Maximum 6 series per chart

Slide sequence per analysis:
- `scorecard_totals` → 1 KPI grid slide (3×2 text boxes with metric name, value, delta)
- `scorecard_dimensions` → 1 horizontal bar slide per dimension (up to 8 slides)
- `detailed_renewals` → table slides (20 rows/slide)
- `churn_list` → table slides
- `churn_reason` → 1 bar chart + 1 table
- `cross_upsell` → 1 stacked bar + 1 table
- `opal_analysis` → 1 KPI slide (attach rate) + 1 bar (pipeline) + 1 table (renewals)
- `oa_analysis` → 1 line slide + 1 bar slide + 1 table
- `eo_deep_dive` → 4 bar slides (EMEA/NAM, Opal correlation, tester type, next product)
- `cms_paas_saas` → 1 dual-line slide + 1 bar slide + 1 table
- `cms_portfolio` → table slides

### Excel Workbook
Use the `xlsx` skill to build the workbook. Sheet structure:

| Sheet | Content |
|---|---|
| README | Description, date, sheet index |
| Scorecard | scorecard_totals KPIs + scorecard_dimensions table |
| Renewals | detailed_renewals |
| Churn | churn_list |
| Churn Reasons | churn_reason summary + detail |
| Cross-Upsell | cross_upsell movements |
| Opal | pipeline + attach rate + renewals (stacked) |
| OA Analytics | portfolio + renewals + usage trend |
| EO Deep Dive | 4 tables |
| CMS PaaS-SaaS | monthly trend + renewal comparison + migration |
| CMS Portfolio | cms_portfolio |

Formatting:
- Header row: fill=`#0037FF`, font=white, bold
- Alternating rows: `#EFF6FF` / white
- ARR columns: `$#,##0`
- Rate columns: `0.0%`
- Count columns: `#,##0`
- Freeze row 1, auto-filter
- Tab colours: Scorecard=`#0037FF`, Renewals=`#22C55E`, Churn=`#EF4444`,
  Cross-Upsell=`#8B5CF6`, Opal=`#F59E0B`, OA=`#06B6D4`, EO=`#10B981`, CMS=`#F97316`

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
| Experiments per customer | `REPORTING.OPTI_APPLICATION.EXPERIMENT_METRICS` + `OA_CUSTOMER_DETAIL` |
| Feature flags per customer | `REPORTING.OPTI_APPLICATION.FEATURE_FLAGS_METRICS_HISTORICAL` + `OA_CUSTOMER_DETAIL` |
