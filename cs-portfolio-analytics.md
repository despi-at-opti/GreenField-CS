---
name: cs-portfolio-analytics
description: >
  Optimizely CS portfolio analytics. You are a world-class data scientist specialising in customer success data and insights. The goal of this task is to create a comprehensive report for CS leadership and operations regarding the entire portfolio and specific products of interest. 

  ALways ask if the user wants the output in pptx, word, pdf or html formats. Ensure graphics fit in page according to the selected format. Use Optimizely brand skill for formatting. Never display results in pie or donut charts. Graphs should interactive and include related data information on a tooltip - when the output format allows for it. 
  
  Include source data table in each case. Include interesting conclusions from the data, what stands out in each graph.
  
  Use information below to guide you. 
---

# CS Portfolio Analytics

This skill covers the data sources, business logic, metric definitions, and analyses
for Optimizely CS portfolio analytics. All content is based on validated Snowflake
tables in the Optimizely data warehouse.

## Before Starting Any Analysis

Always ask the user how they want the data presented before running queries or building output. For example:

- Table in chat?
- Downloadable Excel / CSV?
- A written summary / narrative?
- A slide-ready format?
- A specific set of dimensions or filters to focus on?

Keep it to one short question — don't list every option every time. Use judgement based on context (e.g. if they've asked for a "report", ask table vs narrative; if they've asked to "run a query", just confirm the output format).

---

## Standard Analyses Required

When building any CS portfolio analysis, always cover:

1. **Scorecard**: Renewals (count + ARR $), Churn (count + ARR $), Renewal Rate
   - **Monthly report**: last 6 months (or 12 if user requests), MoM delta + % change per metric
   - **Quarterly report**: QoQ delta + YoY delta + % change per metric
   - Default to quarterly when cadence is not specified
   - Always include: vs target, up/down/on-point indicator
2. **Trend line**: monthly (last 6–12 months) or quarterly depending on report cadence
3. **Dimensions**: Global → Region → Territory → ARR band → SFDC segment → Revenue segment → Product grouping → Product group → Single/Multi-solution → PRIMARY_CSM
4. **Detailed list**: account-level table (see below `references/semantics_and_analyses` → Analyses → section 1)
5. **Cross-sell / upsell**: original products → new products, focus on EO, EC, AI, CMS
6. **Churn reasons**: SF new churn code + web enrichment for top accounts
7. **Opal**: pipeline, attach rate, renewals/RR, credit consumption
8. **EO deep dive**: EMEA vs NAM, opal-attach correlation, WebEx → next product probability
9. **CMS migration**: PaaS → SaaS ARR movement
10. **CMS portfolio**: manager, account, contract dates, region, segment, QBR status, next call prep

---

## Quick Reference: Which Table to Use

| Need | Table |
|---|---|
| Product-level renewal rates, EO/EC/AI splits | `EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP` (deduplicate with QUALIFY) |
| Account-level totals, global headline RR | `EXEC_DECK_RENEWAL_RATES_CUSTOMER` |
| Product-solution renewal rates (leanest view) | `EXEC_DECK_RENEWAL_RATES_PRODUCT_SOLUTION` |
| ARR snapshots, Opal attach, cross-sell | `SST_REPORT` (filter `DAY(SNAPSHOT_DATE) >= 28`, exclude EOL) |
| Salesforce contract context, TCV, SCO | `ARR_REPORT` |
| Churn reasons, pipeline, live Salesforce data | `RENEWAL_OPPORTUNITY` (aggregate at MCID × OPPORTUNITY_ID) |
| Experimentation adoption trends MoM/YoY | `EXP_CUSTOMER_ADOPTION_BRAVE` |
| Experiments per customer (count/avg/median) | `EXPERIMENT_METRICS` + `OA_CUSTOMER_DETAIL` |
| Feature flags per customer (count/avg/median) | `FEATURE_FLAGS_METRICS_HISTORICAL` + `OA_CUSTOMER_DETAIL` |

---

## Universal Query Rules

1. **EXEC_DECK_PG duplicates**: always add `QUALIFY ROW_NUMBER() OVER (PARTITION BY MASTER_CUSTOMER_ID, PRODUCT_GROUP_CLEANED, DATE_YM ORDER BY DATE_YM DESC) = 1`
2. **SST_REPORT snapshots**: always filter `DAY(SNAPSHOT_DATE) >= 28` for end-of-month; never sum across multiple dates without grouping
3. **SST_REPORT EOL**: always add `AND NEW_PRODUCT_SOLUTION != 'EOL'`
4. **RENEWAL_OPP fan-out**: `RENEWAL_FINAL_AMOUNT_USD` repeats per product line — always `MAX()` grouped by `MCID + OPPORTUNITY_ID`
5. **Opal attach**: use SST_REPORT or EXEC_DECK_PG logic — do NOT use `RENEWAL_OPP.IS_OPAL` (only ~62 TRUE records)
6. **MCID = MASTER_CUSTOMER_ID**: same identifier, different column names across tables
7. **DATE_YQ format**: `'YYYY-QN'` with hyphen (e.g. `'2026-Q1'`); CONTRACT_START_QUARTER uses space (`'2026 Q1'`)

---

## Core Metric Formulas

**Renewal Rate**: `(ARR_RENEWAL + ARR_CHURN) / ARR_RENEWAL`  
ARR_CHURN is always negative. Result is a decimal (0.81 = 81%).

**High Tester**: avg experiments run per month >= 9  
**Low Tester**: avg experiments run per month < 9

**Revenue Segmentation**:
- Enterprise: `ARR_RENEWAL >= 250,000`
- Mid-Market: `ARR_RENEWAL >= 100,000`
- Digital: `ARR_RENEWAL < 100,000`

**ARR Bands**: `<= $100k` | `$100k–$250k` | `$250k–$500k` | `$500k+`

---

## Reference Files

Load the relevant reference file when starting any query or analysis:

- **`data_catalog`** — All source tables: full paths, aliases, PKs, grains,
  when to use, critical query rules, and join patterns. Read this first for any query task.

# CS Portfolio Analytics — Data Catalog

Reference guide for all Snowflake source tables used in CS portfolio analytics, renewals reporting, and ARR analysis.

---

## Source Tables at a Glance

| Alias | Full Table Path | Grain | Use For |
|---|---|---|---|
| EXEC_DECK_PG | `REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP` | MCID × Product Group × Month | Product-level RR, EO/EC/AI splits, regional cuts |
| EXEC_DECK_CUS | `REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_CUSTOMER` | MCID × Quarter | Account-level totals, global headline RR |
| EXEC_DECK_SOL | `REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_PRODUCT_SOLUTION` | MCID × Product Solution × Month | Product-solution RR (leanest view, 14 cols) |
| SST_REPORT | `REPORTING.ARR_SST.SST_REPORT` | MCID × SKU × Snapshot Date | ARR snapshots, Opal attach, cross-sell tracking |
| ARR_REPORT | `REPORTING.ARR_SST.ARR_REPORT` | MCID × SKU × Snapshot Date | Salesforce contract context, TCV, SCO changes |
| RENEWAL_OPP | `REPORTING.GTM_ANALYTICS.RENEWAL_OPPORTUNITY` | MCID × Opp ID × Product Line | pipeline, live Salesforce data |
| brave_customer_adoption | `REPORTING.GTM_ANALYTICS.EXP_CUSTOMER_ADOPTION_BRAVE` | MCID × Month | Experimentation adoption MoM/YoY |
| experiments_per_customer | `REPORTING.OPTI_APPLICATION.EXPERIMENT_METRICS` + `OA_CUSTOMER_DETAIL` | customer_id | Experiments run per customer |
| feat_flags_per_customer | `REPORTING.OPTI_APPLICATION.FEATURE_FLAGS_METRICS_HISTORICAL` + `OA_CUSTOMER_DETAIL` | customer_id | Feature flags activated per customer |
| RAW_OPP | `REPORTING.SALESFORCE.RAW_OPPORTUNITY_REPORT`  | one row per Opportunity (ID) | new churn codes, type of churn, churn category |
---

## Table Detail

### EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP (EXEC_DECK_PG)

**Full path**: `REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP`  
**PK**: `MASTER_CUSTOMER_ID`  
**Grain**: `MASTER_CUSTOMER_ID × PRODUCT_GROUP_CLEANED × DATE_YM`  
**When to use**: Product-level renewal rates, EO/EC/AI splits, regional and territory cuts, good/bad fit analysis.

⚠️ **Contains ~360 known duplicate rows.** Always deduplicate:
```sql
QUALIFY ROW_NUMBER() OVER (
  PARTITION BY MASTER_CUSTOMER_ID, PRODUCT_GROUP_CLEANED, DATE_YM
  ORDER BY DATE_YM DESC) = 1
```

---

### EXEC_DECK_RENEWAL_RATES_CUSTOMER (EXEC_DECK_CUS)

**Full path**: `REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_CUSTOMER`  
**PK**: `MASTER_CUSTOMER_ID`  
**Grain**: `MASTER_CUSTOMER_ID × DATE_YQ`  
**When to use**: Account-level queries, global headline renewal rate, ARR band cuts, portfolio totals.  
**Note**: Folds all product groups into a single account total.

---

### EXEC_DECK_RENEWAL_RATES_PRODUCT_SOLUTION (EXEC_DECK_SOL)

**Full path**: `REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_PRODUCT_SOLUTION`  
**PK**: `MASTER_CUSTOMER_ID`  
**Grain**: One row = one product solution renewal event per customer per year-month / year-quarter  
**When to use**: Product-solution-level renewal rates for executive reporting.  
**Note**: Leanest of the three EXEC_DECK views (14 columns). Includes `CTA_CREATED` (unique to this view). Sources: CUSTOMER_DETAIL_REPORT, OPTI_SALESFORCE.OPPORTUNITY, Gainsight/CS data (via dbt).

---

### SST_REPORT

**Full path**: `REPORTING.ARR_SST.SST_REPORT`  
**PK**: `MCID`  
**Grain**: `MCID × UPDATED_PRODUCT_GROUP × SNAPSHOT_DATE`  
One row = one subscription line item for one customer, for one product SKU, at one monthly snapshot date.

**When to use**: ARR snapshots, Opal attach, multi/single solution classification, OA contracted customers, cross-sell tracking.

⚠️ **Critical rules**:
- Always filter `DAY(SNAPSHOT_DATE) >= 28` for end-of-month snapshots
- Always exclude EOL: `AND NEW_PRODUCT_SOLUTION != 'EOL'`
- Use `UPDATED_PRODUCT_GROUP` (never `TEMP_PRODUCT_GROUP_LI`)
- `MCID` = `MASTER_CUSTOMER_ID` in EXEC_DECK tables

---

### ARR_REPORT

**Full path**: `REPORTING.ARR_SST.ARR_REPORT`  
**PK**: `MCID`  
**Grain**: One row per subscription line item per customer per SKU per snapshot date. Contains both start-of-month and end-of-month entries (~2× the rows of SST_REPORT).

**When to use**: When you need Salesforce contract context, TCV, or SCO change tracking.

| | ARR_REPORT | SST_REPORT |
|---|---|---|
| Snapshot dates | ~118 (start + end of month) | ~87 (end of month only) |
| Salesforce linkage | ✅ Opp ID, contract ID, TCV | ❌ |
| SCO tracking | ✅ | ❌ |
| Row count | ~1.1M | ~978K |

---

### REPORTING.SALESFORCE.RAW_OPPORTUNITY_REPORT (RAW_OPP)

**Full path**: `REPORTING.SALESFORCE.RAW_OPPORTUNITY_REPORT`  
**PK**: `ID`  
**Grain**: `ID` (one row per opportunity)

**When to use**: New Churn Codes, Source-of-truth Salesforce extract for opportunity-level reporting — pipeline analysis, bookings, churn tracking, win/loss, and forecasting. It's current-state (not snapshotted over time)

⚠️ **Interesting Info**:
It stores every sales opportunity (new business, renewals, upsells, churn/downsell) with fields like:

- Deal info: stage, amount, close date, type, forecast category
- Churn fields: TYPE_OF_CHURN_C, CHURN_CATEGORY_C
- Account/ownership: account ID, owner, AE, territory
- Timestamps: created date, last modified, close date

---

### RENEWAL_OPPORTUNITY (RENEWAL_OPP)

**Full path**: `REPORTING.GTM_ANALYTICS.RENEWAL_OPPORTUNITY`  
**PK**: `MCID`  
**Grain**: `MCID × OPPORTUNITY_ID × product line` (fan-out: multiple rows per deal)

**When to use**: Competitors, product-level pipeline, retained/lost accounts, live Salesforce data.

⚠️ **Critical rules**:
- `RENEWAL_FINAL_AMOUNT_USD` repeats for every product group row on the same opportunity — always use `MAX(RENEWAL_FINAL_AMOUNT_USD)` grouped by `MCID + OPPORTUNITY_ID`
- Do NOT use `IS_OPAL` — only ~62 TRUE records, unreliable

---

### EXP_CUSTOMER_ADOPTION_BRAVE

**Full path**: `REPORTING.GTM_ANALYTICS.EXP_CUSTOMER_ADOPTION_BRAVE`  
**PK**: `MASTER_CUSTOMER_ID`  
**Grain**: Monthly per customer  
**When to use**: Brave experimentation adoption/usage, MoM/YoY/6-month average comparisons.

**Notes**:
- `EXPS_*_COMPARED_TO_*` fields = current month value minus comparison period (positive = growth)
- `EXPERIMENTS_STARTED` uses 1,000-impression CS definition
- `IS_ACTIVE` based on contract status at time of month
- `EARLIEST_EXP_TAT_DATE` / `LATEST_EXP_TAT_DATE` stored as TEXT — cast to DATE before use

---

### EXPERIMENT_METRICS + OA_CUSTOMER_DETAIL

**Full paths**: `REPORTING.OPTI_APPLICATION.EXPERIMENT_METRICS` + `REPORTING.OPTI_APPLICATION.OA_CUSTOMER_DETAIL`  
**PK**: `customer_id`  
**When to use**: Total / avg / min / max / median experiments run by customer by month/quarter/year.

```sql
FROM REPORTING.OPTI_APPLICATION.EXPERIMENT_METRICS em
LEFT JOIN REPORTING.OPTI_APPLICATION.OA_CUSTOMER_DETAIL cd
    ON cd.customer_id = em.customer_id
WHERE em.EXPERIMENT_START_TIME_IMPRESSIONS_REACHED IS NOT NULL
```

---

### FEATURE_FLAGS_METRICS_HISTORICAL + OA_CUSTOMER_DETAIL

**Full paths**: `REPORTING.OPTI_APPLICATION.FEATURE_FLAGS_METRICS_HISTORICAL` + `REPORTING.OPTI_APPLICATION.OA_CUSTOMER_DETAIL`  
**PK**: `customer_id`  
**When to use**: Total / avg / min / max / median feature flags activated by customer by month/quarter/year.

```sql
SELECT
    cd.master_customer_id AS mcid,
    DATE_TRUNC('MONTH',
        CASE
            WHEN ff.flag_activate IS NOT NULL THEN ff.flag_activate
            WHEN ff.flag_activate IS NULL AND ff.feature_flag_status = TRUE THEN ff.flag_created
        END
    ) AS month_start,
    COUNT(DISTINCT ff.feature_flag_id) AS flags_enabled
FROM REPORTING.OPTI_APPLICATION.FEATURE_FLAGS_METRICS_HISTORICAL ff
LEFT JOIN REPORTING.OPTI_APPLICATION.OA_CUSTOMER_DETAIL cd
    ON cd.customer_id = ff.customer_id
WHERE DATE_TRUNC('MONTH',
        CASE
            WHEN ff.flag_activate IS NOT NULL THEN ff.flag_activate
            WHEN ff.flag_activate IS NULL AND ff.feature_flag_status = TRUE THEN ff.flag_created
        END
    ) IS NOT NULL
GROUP BY 1, 2
```

---

## Universal Query Rules (apply always)

1. **EXEC_DECK_PG**: deduplicate with QUALIFY ROW_NUMBER (see above)
2. **SST_REPORT**: `DAY(SNAPSHOT_DATE) >= 28` + `NEW_PRODUCT_SOLUTION != 'EOL'`
3. **RENEWAL_OPP**: `MAX(RENEWAL_FINAL_AMOUNT_USD)` grouped by `MCID + OPPORTUNITY_ID`
4. **Opal attach**: use SST_REPORT or EXEC_DECK logic — never `RENEWAL_OPP.IS_OPAL`
5. **MCID = MASTER_CUSTOMER_ID**: same identifier across tables, different column names
6. **DATE_YQ format**: `'YYYY-QN'` with hyphen e.g. `'2026-Q1'`; CONTRACT_START_QUARTER uses space e.g. `'2026 Q1'`
7. **Quarter → month**: Q1=`03`, Q2=`06`, Q3=`09`, Q4=`12` (use last month of quarter in date filters)


- **`semantics_and_analyses`** — Metric formulas, product group → solution
  mapping, dimension definitions, SQL patterns for common business logic (Opal attach,
  EO attach, single/multi-solution, revenue segmentation, high/low tester), and the
  full catalog of required analyses. Read this for any analysis or metric calculation.

# CS Portfolio Analytics — Metric Definitions & Business Logic

Reference for how key CS metrics are calculated, product group mappings, segmentation logic, and SQL patterns.

---

## Core Metric Formulas

### Renewal Rate
```
(ARR_RENEWAL + ARR_CHURN) / ARR_RENEWAL
```
`ARR_CHURN` is always a negative number. Result is a decimal (0.81 = 81%).

### ARR_CHURN
Negative number representing ARR lost at renewal.

### DOFIT_C (Good Fit / Bad Fit)
Derived from: web traffic, industry, B2B/B2C business model.  
Values: `'Good Fit'` / `'Bad Fit'` / NULL  
~47% populated as of May 2026.

---

## Date & Quarter Formats

| Field | Format | Example |
|---|---|---|
| `DATE_YQ` | `'YYYY-QN'` (hyphen) | `'2026-Q1'` |
| `CONTRACT_START_QTR` | `'YYYY QN'` (space) | `'2026 Q1'` |
| `CONTRACT_START_QUARTER` | `'YYYY QN'` (space) | `'2026 Q1'` |

**Quarter → last month mapping** (for `DATE_YM` filters):
- Q1 → `'03'` | Q2 → `'06'` | Q3 → `'09'` | Q4 → `'12'`

---

## Product Group → Solution Mapping

Use this mapping consistently across all tables:

```sql
CASE
    WHEN PRODUCT_GROUP_CLEANED IN (
        'Analytics', 'Feature Experimentation', 'Web Experimentation',
        'Experimentation Platform', 'Experimentation Addons',
        'Personalization', 'Segmentation'
    ) THEN 'EO'   -- Experience Optimization

    WHEN PRODUCT_GROUP_CLEANED IN (
        'Commerce Connect Non-Retail', 'Product Recommendations',
        'Content Recommendations', 'Content Management PaaS',
        'Content Management SaaS', 'Content Management Addons'
    ) THEN 'EC'   -- Experience Creation

    WHEN PRODUCT_GROUP_CLEANED = 'Opal'
        THEN 'AI'

    WHEN PRODUCT_GROUP_CLEANED IN (
        'Content Management Platform', 'Content Marketing Platform',
        'Digital Asset Management', 'Configured Commerce'
    ) THEN 'CMP'

    WHEN PRODUCT_GROUP_CLEANED IN (
        'EOL - Legacy Siteseeker', 'EOL - Legacy Visitor Intelligence',
        'EOL - Everweb', 'EOL - ImageVault',
        'EOL - Community API', 'EOL - Legacy Ektron'
    ) THEN 'EOL'   -- Exclude from all board metrics

    ELSE 'Other'
END AS PRODUCT_SOLUTION
```

> In SST_REPORT, use `UPDATED_PRODUCT_GROUP` in place of `PRODUCT_GROUP_CLEANED`.

---

## CMS PaaS / SaaS

Track together to monitor migration health.  
PaaS = legacy on-premise (expected to shrink).  
SaaS = modern cloud (expected to grow).

```sql
-- EXEC_DECK_PG
PRODUCT_GROUP_CLEANED IN ('Content Management PaaS', 'Content Management SaaS')

-- SST_REPORT
UPDATED_PRODUCT_GROUP IN ('Content Management PaaS', 'Content Management SaaS')
```

---

## Segmentation

### Revenue-Based Segmentation
```sql
CASE
    WHEN ARR_RENEWAL >= 250000 THEN 'Enterprise'
    WHEN ARR_RENEWAL >= 100000 THEN 'Mid-Market'
    ELSE 'Digital'
END AS REVENUE_SEGMENT
```

### ARR Bands
`<= $100k` | `$100k – $250k` | `$250k – $500k` | `$500k+`

---

## Derived Flags & Classifications

### Single- / Multi-Solution (SST_REPORT)
```sql
IFF(COUNT(DISTINCT
    CASE
        WHEN UPDATED_PRODUCT_GROUP IN (
            'Analytics','Feature Experimentation','Web Experimentation',
            'Experimentation Platform','Experimentation Addons',
            'Personalization','Segmentation') THEN 'EO'
        WHEN UPDATED_PRODUCT_GROUP IN (
            'Commerce Connect Non-Retail','Product Recommendations',
            'Content Recommendations','Content Management PaaS',
            'Content Management SaaS','Content Management Addons',
            'Content Management Platform','Content Marketing Platform',
            'Digital Asset Management','Configured Commerce') THEN 'EC'
        WHEN UPDATED_PRODUCT_GROUP = 'Opal' THEN 'AI'
        ELSE NULL
    END
) > 1, 'Multi-Solution', 'Single-Solution') AS SOL_TYPE
```

### Opal Attach (EXEC_DECK_PG)
```sql
IFF(COUNT(CASE WHEN PRODUCT_GROUP_CLEANED = 'Opal' THEN 1 END)
        OVER (PARTITION BY MASTER_CUSTOMER_ID, DATE_YQ) > 0,
    'Yes', 'No') AS OPAL_ATTACH
```
⚠️ Denominator = EO-attached customers only. Do NOT use `RENEWAL_OPP.IS_OPAL`.

### EO Attach (EXEC_DECK_PG)
```sql
IFF(COUNT(CASE WHEN PRODUCT_GROUP_CLEANED IN (
        'Analytics','Feature Experimentation','Web Experimentation',
        'Experimentation Platform','Experimentation Addons',
        'Personalization','Segmentation') THEN 1 END)
        OVER (PARTITION BY MASTER_CUSTOMER_ID, DATE_YQ) > 0,
    'Yes', 'No') AS EO_ATTACH
```

### High Tester / Low Tester
- **High Tester**: average experiments run per month >= 9
- **Low Tester**: average experiments run per month < 9

### Churn by Type
Source: `REPORTING.SALESFORCE.RAW_OPPORTUNITY_REPORT`  
Use `TYPE_OF_CHURN_C` / `CHURN_CATEGORY_C`.  
> NOTES:
- The changes are planned to be released on April 13 2026
- Field label updated: Type_of_Churn__c → Primary Churn Reason
- API name remains unchanged (`TYPE_OF_CHURN_C`)
- Old values have been deactivated
- `CHURN_CATEGORY_C` is now a formula field (no longer manually editable)

---

## Standard Analyses Required

### Scorecard Metrics
For each metric below, always compute: total, QoQ comparison, YoY comparison, % change, vs target, up/down/on-point indicator.

- Renewals (account count + ARR $)
- Churn (account count + ARR $)
- Renewal Rate

### Dimensions to Break Down By

| Dimension | Notes |
|---|---|
| Global total | Scorecard |
| By quarter | Trend line |
| Region | |
| Territory | |
| ARR bands | `<= $100k`, `$100k–$250k`, `$250k–$500k`, `$500k+` |
| SFDC Segment | EXEC_DECK field |
| Revenue Segment | Enterprise / Mid-Market / Digital (derived) |
| Product grouping | EO, EC, Opal / AI, EOL |
| Product group | Granular PRODUCT_GROUP_CLEANED |
| Product solution | PRODUCT_SOLUTION |
| Single / Multi Solution | |
| PRIMARY_CSM | |

---

## Analysis Catalog

### 1. Detailed Renewals / Churn List (table per quarter)

| Column | Source |
|---|---|
| DATE_YQ | EXEC_DECK |
| Account Name | EXEC_DECK |
| Primary CSM | EXEC_DECK |
| Region | EXEC_DECK |
| Territory | EXEC_DECK |
| Revenue Segment | Derived |
| Single / Multi Solution | SST_REPORT derived |
| Product Groups | EXEC_DECK / SST_REPORT |
| Retained / Churned | `ARR_CHURN < 0` = Churned |
| Churn reason / new code | REPORTING.SALESFORCE.RAW_OPPORTUNITY_REPORT (churned only) |
| Avg experiments per month | EXPERIMENT_METRICS (WebEx customers) |
| Avg flags activated per month | FEATURE_FLAGS_METRICS_HISTORICAL (FX customers) |

---

### 2. Cross-sell / Up-sell Analysis
- Original products → new products
- Focus on EO, EC, AI (Opal), CMS solutions
- Key hypothesis: *"If a customer has Web Experimentation, what is the probability they buy X next?"*

---

### 3. Churn Reason Analysis
- Salesforce new churn code from: `REPORTING.SALESFORCE.RAW_OPPORTUNITY_REPORT` (`TYPE_OF_CHURN_C` + `CHURN_CATEGORY_C`)
- Web search enrichment for top 10–20 accounts

---

### 4. Opal Analysis
- Opal pipeline (stages, ARR)
- Opal attach rate (EO-attached customers as denominator)
- Opal renewals / renewal rate
- Credit consumption vs expected (`ACTUAL / EXPECTED`)

---

### 5. Experimentation Solution (EO) Deep Dive
Focus: Web Experimentation + Feature Experimentation
- EMEA vs NAM renewals / churn QoQ / YoY
- Opal attach — does it correlate with higher renewal rates?
- High Tester vs Low Tester renewal rate comparison
- Cross-sell / upsell patterns: WebEx customer → next likely product

---

### 6. CMS PaaS → SaaS Migration Monitoring
Track PaaS ARR shrinking and SaaS ARR growing over time to assess migration health.

---

### 7. OA / Analytics Monitoring
- Accounts with OA/Analytics product
- Revenue from OA/Analytics
- Usage trends

---

### 8. CMS Portfolio View (table)

| Column | Source |
|---|---|
| CMS Manager (CSM) | EXEC_DECK |
| Account Name | EXEC_DECK |
| Contract Start Date | RENEWAL_OPP |
| Renewal Date | RENEWAL_OPP |
| Region | EXEC_DECK |
| Territory | EXEC_DECK |
| Segment | EXEC_DECK |
| Product Group | EXEC_DECK / SST_REPORT |
| Single / Multi Solution | SST_REPORT derived |
| QBR Completed | EXEC_DECK.QBR_STATUS = 'Completed' |
| Opportunities for next call | RENEWAL_OPP pipeline stage / notes |
