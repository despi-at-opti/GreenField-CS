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
