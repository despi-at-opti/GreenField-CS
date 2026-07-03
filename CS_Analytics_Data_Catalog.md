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
