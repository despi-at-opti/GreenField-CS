# Locked Definitions & Skills

## Region Order
- Always: NA > EMEA > APJ (this is the display and iteration order)

## Product Hierarchy
Hierarchy: Type > Product Solution > Product Line > Product Group > Product (SKU)

### Core
| Product Solution | Product Line | Product Group | Products (SKU) |
|-----------------|--------------|---------------|----------------|
| AI | AI | Opal | Opal |
| Experience Creation | Experience driven Commerce | Commerce Connect Non-Retail | Customized Commerce, Commerce Catalog, Commerce for Dynamics |
| Experience Creation | Recommendations | Product Recommendations | Product Recommendations, Product Email Recommendations |
| Experience Creation | Recommendations | Content Recommendations | Content Recommendations |
| Experience Creation | Content Management (CMS) | Content Management PaaS | CMS PaaS, Content Cloud Platform, Personalized Find |
| Experience Creation | Content Management (CMS) | Content Management SaaS | CMS SaaS |
| Experience Creation | Content Management (CMS) | Content Management Addons | Vercel, Netlify, Content Graph, CMS-HIPPA, Front End Hosting |
| Experience Creation | Content Marketing (CMP) | Content Marketing | Content Marketing Platform, DAM |
| Experience Optimization | Analytics | Analytics | Analytics |
| Experience Optimization | Experiment | Feature Experimentation | Feature Experimentation |
| Experience Optimization | Experiment | Web Experimentation | Web Experimentation, Experiment Personalization |
| Experience Optimization | Experiment | Experimentation Platform | Experimentation Platform |
| Experience Optimization | Experiment | Experimentation Addons | Experiment Collaboration, Contentsquare, Experimentation-HIPPA, Warehouse-Native Scorecard |
| Experience Optimization | Personalization | Personalization | Personalization |
| Experience Optimization | Personalization | Segmentation | Data Platform (ODP), Activation-Add-ons |

### Non-Core
| Product Solution | Product Line | Product Group | Products (SKU) |
|-----------------|--------------|---------------|----------------|
| EOL | Other | EOL-Legacy (various) | Siteseeker, Visitor Intelligence, Everweb, ImageVault, Community API, Ektron |
| Services | Other | Other Services | Expert Services, Onboarding, Premium Support (NTA/CSLM), Education, Other Services |
| Other | Other | Campaign | Campaign |
| Other | Other | Commerce Connect Retail | Customized Commerce, Commerce Catalog, Commerce for Dynamics |
| Other | Other | Delivra | Delivra |
| Other | Other | Configured Commerce | Configured Commerce, Commerce Mobile, Commerce Analytics, PIM |
| Other | Other | Reseller | Content Marketing Platform via Industry Dive |
| Other | Other | Search & Navigation Standalone | Search & Navigation Standalone |
| Other | Other | Legacy NetSpring | Legacy NetSpring |

### Product Category Mapping (for CS Analytics)
This is how REPORTING_CATEGORY_C maps to our analysis categories:
```sql
CASE
    WHEN prod.REPORTING_CATEGORY_C IN ('Web Experimentation', 'Feature Experimentation',
         'Personalization', 'Segmentation', 'Full Platform Experimentation')
         OR prod.REPORTING_CATEGORY_C ILIKE '%Analytics'
         THEN 'Experimentation'  -- = Experience Optimization solution
    WHEN prod.REPORTING_CATEGORY_C = 'Opal' THEN 'Opal'  -- = AI solution
    WHEN prod.REPORTING_CATEGORY_C ILIKE '%CMS%' THEN 'CMS'  -- = Experience Creation/CMS
    ELSE 'Other Products'
END AS product_category
```

### Shorthand & Key Products
| Abbreviation | Full Name | Key Product Groups |
|---|---|---|
| EO | Experience Optimization (= Experimentation) | Web Experimentation (WebExp), Feature Experimentation (FeatExp) |
| EC | Experience Creation | CMS PaaS |
| AI | AI | Opal |

## Region (from TERRITORY_C.NAME)
```sql
CASE WHEN CHARINDEX('-', t.NAME) > 0 THEN LEFT(t.NAME, CHARINDEX('-', t.NAME) - 1)
     ELSE COALESCE(t.NAME, 'Unknown')
END AS region
-- Values: NA, EMEA, APJ. Order: NA > EMEA > APJ.
```

## KOGT (Kickoff to Go-Live Time)
```sql
GREATEST(DATEDIFF('day', oc.KICKOFF_DATE_C, oc.GO_LIVE_DATE_C), 0)
-- Floored at 0. NULL if either date missing.
```

## Active Customer
- STAGE IN ('Delivery', 'Delivery - Do Not Invoice', 'On Hold', 'Planning')
- LAST_TIME_ENTRY_CHANGE_C >= CURRENT_DATE() - 60 days

## Renewal Rate
```sql
(ARR_RENEWAL + ARR_CHURN) / NULLIF(ARR_RENEWAL, 0)
-- Net retention. Churn is negative.
```

## Renewal Cycle (Cohort/Vintage)
- Quarterly grain: gaps >=12 months between quarterly appearances = new cycle
- Source: ARR_REPORT (product_solution IN 'Experience Optimization', 'AI')

## Retention Cohort Analysis
- Cohort dimension: go-live quarter (YYYY-QN)
- Eligible = go-live >=12mo ago (time must have elapsed for renewal to be possible)
- Renewed = first renewal event >=12mo post go-live
- % Renewed = Renewed / Eligible (not base — avoids immature-cohort deflation)

## Standard Filters (PBI-aligned)
- ELEMENT_NAME NOT LIKE '%Overage%', '%Shadowing%', '%Discount%', '%DO NOT USE%'
- PRODUCT_SKU_C NOT IN ('ESC-ACC', 'ES-FIXP', 'ES-GMO-REC', 'ES-SUBSVR')
- REPORTING_CATEGORY_C NOT IN ('Shadowing', 'Overage')
- ACCOUNT_NAME NOT ILIKE '%test%'
- Proposal BU = 'Onboarding'

## Key Tables
| Alias | Table |
|-------|-------|
| oc | REPORTING.CUSTOMER_REPORTS.ONBOARDING_CUSTOMERS |
| dg | VAULT_FIVETRAN.OPTI_SALESFORCE.KIMBLE_ONE_DELIVERY_GROUP_C |
| de | VAULT_FIVETRAN.OPTI_SALESFORCE.KIMBLE_ONE_DELIVERY_ELEMENT_C |
| prod | VAULT_FIVETRAN.OPTI_SALESFORCE.KIMBLE_ONE_PRODUCT_C |
| a | TRANSFORM.OPTI_SALESFORCE.STG_OPTI_SALESFORCE_ACCOUNT |
| t | VAULT_FIVETRAN.OPTI_SALESFORCE.TERRITORY_C |
| p | VAULT_FIVETRAN.OPTI_SALESFORCE.KIMBLE_ONE_PROPOSAL_C |
| bu | VAULT_FIVETRAN.OPTI_SALESFORCE.KIMBLE_ONE_BUSINESS_UNIT_C |

## Snowflake Connection
- Connection name: `OPTIMIZELY_DATA_SERVICES`
- Auth: Browser-based SSO (externalbrowser)
- CLI env var: `SNOWFLAKE_CONNECTION_NAME=OPTIMIZELY_DATA_SERVICES`

## HTML Visual Standards

### Page Structure
- **Header**: Dark green sticky top bar, 'CS Portfolio Analytics' title + quarter/date badge.
- **Navigation**: Fixed left sidebar with links to each analysis section.
- **Content width**: Max 1280px, centered.
- **Sections**: White cards with rounded corners + shadow. One card per analysis.
- **Time window badge**: Each section shows its own time context in the period-badge next to the title:
  - Quarter-based analyses: `2026-Q2`
  - Onboarding metrics: `Go-Live ≥ {go_live_from}`
  - Lookback analyses: `L6M: {start} → {end}` or `{start_date} → {end_date}`
  - Always explicit — never assume the user knows which window applies.
- **Footer**: `Generated {date} | Optimizely CS Analytics | Despi Evangelakou`
- **Print/PDF**: Page breaks between sections. Hide sidebar + header on print.

### Layout
- **Tables**: Dark green header (#1A3D2B), white text, zebra rows (even=frost), sage borders. Exception: cohort-retention tables use green gradient heatmap.
- **KPI cards**: Flex row, nowrap, overflow-x:auto. Left accent color per metric. Min-width:90px, flex:1.
- **Export buttons**: Inline with section/table title, small green button (`background:#1A3D2B;color:white;border-radius:4px;font-size:10px`).
- **Methodology**: Always collapsible `<details>` at top of every analysis section.

### Charts (Chart.js)
- **All charts**: Legend at bottom. Short descriptive title at top.
- **Bar charts**: Solid dark green (#1A3D2B), borderRadius:4, vertical. Use horizontal when >8 categories.
- **Stacked bars**: For composition/breakdown (e.g., churn types).
- **Line charts**: No y-axis. Data labels on every point with color-coded background. Scale axes to fill canvas (no wasted whitespace).
- **Histograms**: Solid dark green bars + KDE (kernel density estimate) overlay line for distribution shape. Stats line below title: `n={n} | Mean={mean}d | Median={median}d | Bins={bins}`. Freedman-Diaconis rule for bin width.
- **Sankey charts**: For flow visualization (cross-sell/upsell movements, stage transitions). Already in use for cross_upsell analysis.
- **Pie/donut**: Never use. Use horizontal bars for composition instead.

### Typography (charts)
- Section title: 15px bold
- Chart title/subtitle: 13px gray
- Axis labels: 11px
- Data labels: 10px, color-coded background matching series color

### Colors
- Primary: #1A3D2B (forest/dark green)
- Accent: #AAEE44 (lime)
- Palette: ["#1A3D2B", "#AAEE44", "#8ECFDB", "#F0A0A8", "#2A6650", "#F59E0B", "#4A9A3C", "#7A3D5A"]
- Regions: NA=#1A3D2B, EMEA=#8ECFDB, APJ=#F0A0A8
- Products: Experimentation=#1A3D2B, Opal=#7A3D5A, CMS=#F59E0B, Other=#6B7280
- Retention heatmap: green gradient (darker=higher %, lighter/gray=lower/empty)

### Cohort-Retention Analysis Format
- **Structure**: Line chart at top → heatmap table below.
- **Line chart**: X-axis = renewal cycle (1st, 2nd, 3rd...), Y-axis = accounts count. One line per cohort year. Legend at bottom.
- **Heatmap table**: Rows = cohort (e.g., "2024 cohort"). Columns = "1st Renewal", "2nd Renewal", "3rd Renewal", etc. (always ordinal labels).
- **Cell format**: `{count} ({%})` — e.g., `42 (67%)`. % = accounts at this cycle / accounts at 1st renewal (base).
- **Color gradient**: Dark green (100%) → lighter green → gray/empty (no data yet).
- **Empty cells**: Gray background, no text (cohort hasn't reached that cycle yet).
- **Cycle labels**: Always ordinal: "1st Renewal", "2nd Renewal", "3rd Renewal", "4th Renewal", "5th Renewal". Never "Cycle 1".
