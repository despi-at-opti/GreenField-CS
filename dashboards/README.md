# CS Leadership Dashboards

Automated HTML dashboards for monthly CS leadership reporting.
Built in Optimizely brand style. Output is self-contained HTML with interactive Plotly charts.

---

## Structure

```
dashboards/
  scripts/
    utils.py               ← Brand colors, HTML helpers, shared functions
    01_global_snapshot.py  ← Global KPI tiles + trend lines
    02_breakdowns.py       ← ARR/Churn/RR by Region, Segment, Product, ARR Band
    03_deep_analyses.py    ← Churn codes, accounts, EO/OA/CMS/Opal/Cross-sell
    run_dashboards.py      ← Orchestrator — runs all scripts
  data/                    ← JSON files saved from Snowflake queries (auto-populated)
  output/                  ← Generated HTML dashboards
  README.md
```

---

## How to Generate Dashboards

### Step 1 — Run the Snowflake queries

In Claude (Cowork), ask:

> "Run CS analytics for 2026-Q1 and save data for dashboards"

Claude will use the `cs-portfolio-analytics` skill to:
1. Run all 11 SQL queries against Snowflake
2. Save each result set to `dashboards/data/` as JSON files
3. Call `run_dashboards.py` to generate the HTML output

### Step 2 — Generate HTML manually (if needed)

```bash
cd "GreenField CS/dashboards/scripts"

# All three dashboards
python run_dashboards.py --quarter 2026-Q1

# Only one dashboard
python run_dashboards.py --quarter 2026-Q1 --only global
python run_dashboards.py --quarter 2026-Q1 --only breakdowns
python run_dashboards.py --quarter 2026-Q1 --only deep

# Open in browser after generation
python run_dashboards.py --quarter 2026-Q1 --open
```

---

## Dashboard Descriptions

### 01 — Global Snapshot (`01_global_snapshot.html`)
- **KPI tiles**: Total ARR, Active Accounts, Total Churn ARR, Overall Renewal Rate, EO RR, EC RR, Opal Attach Rate
- Each tile shows current value + QoQ delta + YoY delta
- **Trend charts**: ARR & Churn over time, Renewal Rate vs rolling average
- **Opal pipeline** bar chart by stage
- Source: `01_scorecard_totals`, `07_opal_analysis`, `02_scorecard_dimensions`

### 02 — Breakdowns (`02_breakdowns.html`)
- One section per dimension: Region, Revenue Segment, Solution Type (single/multi), Product Solution (EO/EC/AI/CMP), ARR Band, Territory, Product Group
- Each section: horizontal bar charts (ARR + RR), sortable table, CSV download
- Source: `02_scorecard_dimensions`

### 03 — Deep Analyses (`03_deep_analyses.html`)
- **Churn Codes**: Bar charts by type & category, account-level detail table
- **Top Accounts**: Top churned + top renewed accounts with full detail
- **EO Deep Dive**: Region comparison (EMEA/NAM QoQ), Opal attach correlation, high/low tester RR, next product probability
- **OA Analysis**: ARR & account trend, regional breakdown, customer list
- **CMS PaaS→SaaS**: Migration trend line, upcoming PaaS renewals table, portfolio table
- **Cross-Sell / Upsell**: Stacked bar (added vs lost ARR by product), movement table
- Source: queries 03–11

---

## Data File Format

Each JSON file in `data/` is a list of row dicts matching the column names from Snowflake:

```json
[
  {"current_quarter": "2026-Q1", "current_renewal_arr": 12500000, ...},
  ...
]
```

Multi-query files (07–10) include a `_section` tag on each row to identify which
sub-query the row came from (e.g. `"_section": "pipeline"` for Opal pipeline data).

---

## Adding Trend Data

To enable the trend line charts in the Global Snapshot, save multiple quarters of
scorecard data in `data/01_scorecard_trend.json`:

```json
[
  {"quarter": "2025-Q2", "renewal_arr": 11000000, "renewal_rate": 0.88, "churn_arr": -1320000},
  {"quarter": "2025-Q3", "renewal_arr": 11500000, "renewal_rate": 0.89, "churn_arr": -1265000},
  ...
]
```

Or, run `01_scorecard_totals.sql` for each prior quarter and append all rows to
`01_scorecard_totals.json` (one row per quarter, each with `current_quarter` set).

---

## Brand Reference

| Color        | Hex       | Usage                          |
|---|---|---|
| Primary Blue | `#0037FF` | Headers, KPI accents, Chart 1  |
| Orange       | `#FF5100` | Highlights, alerts, Chart 2    |
| Green        | `#22C55E` | Retained, positive delta       |
| Red          | `#EF4444` | Churn, negative delta          |
| Amber        | `#F59E0B` | On-target, neutral, avg line   |

---

## Source Tables

| Dashboard | Snowflake Tables |
|---|---|
| Global Snapshot | `EXEC_DECK_RENEWAL_RATES_CUSTOMER`, `RENEWAL_OPPORTUNITY` |
| Breakdowns | `EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP` |
| Churn Codes | `RAW_OPPORTUNITY_REPORT`, `EXEC_DECK_RENEWAL_RATES_CUSTOMER` |
| EO Deep Dive | `EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP`, `EXPERIMENT_METRICS`, `SST_REPORT` |
| OA Analysis | `SST_REPORT`, `OA_CUSTOMER_DETAIL` |
| CMS PaaS→SaaS | `SST_REPORT`, `EXEC_DECK_RENEWAL_RATES_CUSTOMER` |
| Cross-Sell/Upsell | `SST_REPORT` (two snapshot dates) |
