-- =============================================================================
-- 02_scorecard_dimensions.sql
-- Renewal Scorecard — Breakdown by Dimension
-- =============================================================================
-- Description : Returns renewal KPIs split across multiple dimensions in one
--               result set via UNION ALL. Each row represents one dimension
--               value within one dimension type.
--
-- Source      : REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP
--               Deduplicated per QUALIFY rule (see dedup CTE below).
--               Grain after dedup: MASTER_CUSTOMER_ID × PRODUCT_GROUP_CLEANED × DATE_YM
--
-- Parameters  :
--   :target_quarter  VARCHAR  Target quarter in 'YYYY-QN' format, e.g. '2026-Q1'
--
-- Output columns (all sections) :
--   dimension_type   | dimension_value | renewal_count | renewal_arr
--   churn_count      | churn_arr       | renewal_rate
--
-- Renewal Rate formula : (ARR_RENEWAL + ARR_CHURN) / ARR_RENEWAL
-- ARR_CHURN is always negative.
--
-- Product group → solution mapping
--   EO  : Analytics, Feature Experimentation, Web Experimentation,
--          Experimentation Platform, Experimentation Addons, Personalization, Segmentation
--   EC  : Commerce Connect Non-Retail, Product Recommendations, Content Recommendations,
--          Content Management PaaS, Content Management SaaS, Content Management Addons
--   AI  : Opal
--   CMP : Content Management Platform, Content Marketing Platform,
--          Digital Asset Management, Configured Commerce
--   EOL : EOL - Legacy Siteseeker, EOL - Legacy Visitor Intelligence, EOL - Everweb,
--          EOL - ImageVault, EOL - Community API, EOL - Legacy Ektron
--
-- Revenue Segment : Enterprise >= 250k | Mid-Market >= 100k | else Digital
-- ARR Bands       : <=100k | 100k-250k | 250k-500k | 500k+
-- =============================================================================

WITH

-- ---------------------------------------------------------------------------
-- 1. Deduplicate EXEC_DECK_PG
--    Rule: one row per (MASTER_CUSTOMER_ID, PRODUCT_GROUP_CLEANED, DATE_YM)
--    keeping the latest by DATE_YM (per catalog requirement).
-- ---------------------------------------------------------------------------
dedup AS (
    SELECT *
    FROM REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY MASTER_CUSTOMER_ID, PRODUCT_GROUP_CLEANED, DATE_YM
        ORDER BY DATE_YM DESC
    ) = 1
),

-- ---------------------------------------------------------------------------
-- 2. Filter to target quarter
-- ---------------------------------------------------------------------------
filtered AS (
    SELECT *
    FROM dedup
    WHERE DATE_YQ = :target_quarter
),

-- ---------------------------------------------------------------------------
-- 3. Helper: map PRODUCT_GROUP_CLEANED → PRODUCT_SOLUTION (exclude EOL)
-- ---------------------------------------------------------------------------
mapped AS (
    SELECT
        f.*,
        CASE
            WHEN PRODUCT_GROUP_CLEANED IN (
                'Analytics', 'Feature Experimentation', 'Web Experimentation',
                'Experimentation Platform', 'Experimentation Addons',
                'Personalization', 'Segmentation'
            )                                                    THEN 'EO'
            WHEN PRODUCT_GROUP_CLEANED IN (
                'Commerce Connect Non-Retail', 'Product Recommendations',
                'Content Recommendations', 'Content Management PaaS',
                'Content Management SaaS', 'Content Management Addons'
            )                                                    THEN 'EC'
            WHEN PRODUCT_GROUP_CLEANED = 'Opal'                  THEN 'AI'
            WHEN PRODUCT_GROUP_CLEANED IN (
                'Content Management Platform', 'Content Marketing Platform',
                'Digital Asset Management', 'Configured Commerce'
            )                                                    THEN 'CMP'
            WHEN PRODUCT_GROUP_CLEANED LIKE 'EOL%'              THEN 'EOL'
            ELSE 'Other'
        END                                                      AS product_solution,

        -- Revenue segment (based on ARR_RENEWAL at the account level;
        -- using SUM across product groups for the customer)
        CASE
            WHEN ARR_RENEWAL >= 250000 THEN 'Enterprise'
            WHEN ARR_RENEWAL >= 100000 THEN 'Mid-Market'
            ELSE 'Digital'
        END                                                      AS revenue_segment,

        -- ARR Band
        CASE
            WHEN ARR_RENEWAL <= 100000  THEN '<=100k'
            WHEN ARR_RENEWAL <= 250000  THEN '100k-250k'
            WHEN ARR_RENEWAL <= 500000  THEN '250k-500k'
            ELSE '500k+'
        END                                                      AS arr_band

    FROM filtered f
),

-- ---------------------------------------------------------------------------
-- 4. Account-level ARR (needed for segment / band derivations at account grain)
--    Aggregate across product groups per customer
-- ---------------------------------------------------------------------------
account_arr AS (
    SELECT
        MASTER_CUSTOMER_ID,
        SUM(ARR_RENEWAL)                                         AS account_renewal_arr,
        SUM(ARR_CHURN)                                           AS account_churn_arr,
        -- Segment based on total account ARR
        CASE
            WHEN SUM(ARR_RENEWAL) >= 250000 THEN 'Enterprise'
            WHEN SUM(ARR_RENEWAL) >= 100000 THEN 'Mid-Market'
            ELSE 'Digital'
        END                                                      AS revenue_segment,
        CASE
            WHEN SUM(ARR_RENEWAL) <= 100000  THEN '<=100k'
            WHEN SUM(ARR_RENEWAL) <= 250000  THEN '100k-250k'
            WHEN SUM(ARR_RENEWAL) <= 500000  THEN '250k-500k'
            ELSE '500k+'
        END                                                      AS arr_band
    FROM filtered
    GROUP BY MASTER_CUSTOMER_ID
),

-- ---------------------------------------------------------------------------
-- 5. Single/Multi solution flag (distinct non-EOL product solutions per MCID)
-- ---------------------------------------------------------------------------
sol_count AS (
    SELECT
        MASTER_CUSTOMER_ID,
        COUNT(DISTINCT
            CASE
                WHEN PRODUCT_GROUP_CLEANED LIKE 'EOL%' THEN NULL
                ELSE CASE
                    WHEN PRODUCT_GROUP_CLEANED IN (
                        'Analytics', 'Feature Experimentation', 'Web Experimentation',
                        'Experimentation Platform', 'Experimentation Addons',
                        'Personalization', 'Segmentation'
                    ) THEN 'EO'
                    WHEN PRODUCT_GROUP_CLEANED IN (
                        'Commerce Connect Non-Retail', 'Product Recommendations',
                        'Content Recommendations', 'Content Management PaaS',
                        'Content Management SaaS', 'Content Management Addons'
                    ) THEN 'EC'
                    WHEN PRODUCT_GROUP_CLEANED = 'Opal' THEN 'AI'
                    WHEN PRODUCT_GROUP_CLEANED IN (
                        'Content Management Platform', 'Content Marketing Platform',
                        'Digital Asset Management', 'Configured Commerce'
                    ) THEN 'CMP'
                    ELSE NULL
                END
            END
        )                                                        AS solution_count
    FROM filtered
    GROUP BY MASTER_CUSTOMER_ID
)

-- =============================================================================
-- FINAL UNION ALL — one section per dimension type
-- =============================================================================

-- ---------------------------------------------------------------------------
-- SECTION 1: By REGION
-- ---------------------------------------------------------------------------
SELECT
    'Region'                                                     AS dimension_type,
    COALESCE(REGION, 'Unknown')                                  AS dimension_value,
    COUNT(DISTINCT CASE WHEN ARR_RENEWAL > 0
          THEN MASTER_CUSTOMER_ID END)                           AS renewal_count,
    ROUND(SUM(ARR_RENEWAL), 2)                                   AS renewal_arr,
    COUNT(DISTINCT CASE WHEN ARR_CHURN < 0
          THEN MASTER_CUSTOMER_ID END)                           AS churn_count,
    ROUND(SUM(ARR_CHURN), 2)                                     AS churn_arr,
    ROUND(
        (SUM(ARR_RENEWAL) + SUM(ARR_CHURN))
        / NULLIF(SUM(ARR_RENEWAL), 0), 4
    )                                                            AS renewal_rate
FROM filtered
GROUP BY REGION

UNION ALL

-- ---------------------------------------------------------------------------
-- SECTION 2: By TERRITORY
-- ---------------------------------------------------------------------------
SELECT
    'Territory'                                                  AS dimension_type,
    COALESCE(TERRITORY, 'Unknown')                               AS dimension_value,
    COUNT(DISTINCT CASE WHEN ARR_RENEWAL > 0
          THEN MASTER_CUSTOMER_ID END)                           AS renewal_count,
    ROUND(SUM(ARR_RENEWAL), 2)                                   AS renewal_arr,
    COUNT(DISTINCT CASE WHEN ARR_CHURN < 0
          THEN MASTER_CUSTOMER_ID END)                           AS churn_count,
    ROUND(SUM(ARR_CHURN), 2)                                     AS churn_arr,
    ROUND(
        (SUM(ARR_RENEWAL) + SUM(ARR_CHURN))
        / NULLIF(SUM(ARR_RENEWAL), 0), 4
    )                                                            AS renewal_rate
FROM filtered
GROUP BY TERRITORY

UNION ALL

-- ---------------------------------------------------------------------------
-- SECTION 3: By ARR Band (account-level ARR drives the band)
-- ---------------------------------------------------------------------------
SELECT
    'ARR Band'                                                   AS dimension_type,
    aa.arr_band                                                  AS dimension_value,
    COUNT(DISTINCT CASE WHEN aa.account_renewal_arr > 0
          THEN aa.MASTER_CUSTOMER_ID END)                        AS renewal_count,
    ROUND(SUM(aa.account_renewal_arr), 2)                        AS renewal_arr,
    COUNT(DISTINCT CASE WHEN aa.account_churn_arr < 0
          THEN aa.MASTER_CUSTOMER_ID END)                        AS churn_count,
    ROUND(SUM(aa.account_churn_arr), 2)                          AS churn_arr,
    ROUND(
        (SUM(aa.account_renewal_arr) + SUM(aa.account_churn_arr))
        / NULLIF(SUM(aa.account_renewal_arr), 0), 4
    )                                                            AS renewal_rate
FROM account_arr aa
GROUP BY aa.arr_band

UNION ALL

-- ---------------------------------------------------------------------------
-- SECTION 4: By SFDC_SEGMENT (as stored on EXEC_DECK_PG)
-- ---------------------------------------------------------------------------
SELECT
    'SFDC Segment'                                               AS dimension_type,
    COALESCE(SFDC_SEGMENT, 'Unknown')                            AS dimension_value,
    COUNT(DISTINCT CASE WHEN ARR_RENEWAL > 0
          THEN MASTER_CUSTOMER_ID END)                           AS renewal_count,
    ROUND(SUM(ARR_RENEWAL), 2)                                   AS renewal_arr,
    COUNT(DISTINCT CASE WHEN ARR_CHURN < 0
          THEN MASTER_CUSTOMER_ID END)                           AS churn_count,
    ROUND(SUM(ARR_CHURN), 2)                                     AS churn_arr,
    ROUND(
        (SUM(ARR_RENEWAL) + SUM(ARR_CHURN))
        / NULLIF(SUM(ARR_RENEWAL), 0), 4
    )                                                            AS renewal_rate
FROM filtered
GROUP BY SFDC_SEGMENT

UNION ALL

-- ---------------------------------------------------------------------------
-- SECTION 5: By REVENUE_SEGMENT (derived: Enterprise / Mid-Market / Digital)
--            Derived at account level using total account ARR.
-- ---------------------------------------------------------------------------
SELECT
    'Revenue Segment'                                            AS dimension_type,
    aa.revenue_segment                                           AS dimension_value,
    COUNT(DISTINCT CASE WHEN aa.account_renewal_arr > 0
          THEN aa.MASTER_CUSTOMER_ID END)                        AS renewal_count,
    ROUND(SUM(aa.account_renewal_arr), 2)                        AS renewal_arr,
    COUNT(DISTINCT CASE WHEN aa.account_churn_arr < 0
          THEN aa.MASTER_CUSTOMER_ID END)                        AS churn_count,
    ROUND(SUM(aa.account_churn_arr), 2)                          AS churn_arr,
    ROUND(
        (SUM(aa.account_renewal_arr) + SUM(aa.account_churn_arr))
        / NULLIF(SUM(aa.account_renewal_arr), 0), 4
    )                                                            AS renewal_rate
FROM account_arr aa
GROUP BY aa.revenue_segment

UNION ALL

-- ---------------------------------------------------------------------------
-- SECTION 6: By PRODUCT_SOLUTION (EO / EC / AI / CMP — EOL excluded)
-- ---------------------------------------------------------------------------
SELECT
    'Product Solution'                                           AS dimension_type,
    m.product_solution                                           AS dimension_value,
    COUNT(DISTINCT CASE WHEN ARR_RENEWAL > 0
          THEN MASTER_CUSTOMER_ID END)                           AS renewal_count,
    ROUND(SUM(ARR_RENEWAL), 2)                                   AS renewal_arr,
    COUNT(DISTINCT CASE WHEN ARR_CHURN < 0
          THEN MASTER_CUSTOMER_ID END)                           AS churn_count,
    ROUND(SUM(ARR_CHURN), 2)                                     AS churn_arr,
    ROUND(
        (SUM(ARR_RENEWAL) + SUM(ARR_CHURN))
        / NULLIF(SUM(ARR_RENEWAL), 0), 4
    )                                                            AS renewal_rate
FROM mapped m
WHERE m.product_solution != 'EOL'
GROUP BY m.product_solution

UNION ALL

-- ---------------------------------------------------------------------------
-- SECTION 7: By PRODUCT_GROUP_CLEANED (granular — EOL groups excluded)
-- ---------------------------------------------------------------------------
SELECT
    'Product Group'                                              AS dimension_type,
    PRODUCT_GROUP_CLEANED                                        AS dimension_value,
    COUNT(DISTINCT CASE WHEN ARR_RENEWAL > 0
          THEN MASTER_CUSTOMER_ID END)                           AS renewal_count,
    ROUND(SUM(ARR_RENEWAL), 2)                                   AS renewal_arr,
    COUNT(DISTINCT CASE WHEN ARR_CHURN < 0
          THEN MASTER_CUSTOMER_ID END)                           AS churn_count,
    ROUND(SUM(ARR_CHURN), 2)                                     AS churn_arr,
    ROUND(
        (SUM(ARR_RENEWAL) + SUM(ARR_CHURN))
        / NULLIF(SUM(ARR_RENEWAL), 0), 4
    )                                                            AS renewal_rate
FROM filtered
WHERE PRODUCT_GROUP_CLEANED NOT LIKE 'EOL%'
GROUP BY PRODUCT_GROUP_CLEANED

UNION ALL

-- ---------------------------------------------------------------------------
-- SECTION 8: Single vs Multi-Solution
--            Single = customer has exactly 1 distinct non-EOL product solution
--            Multi  = customer has 2+ distinct non-EOL product solutions
-- ---------------------------------------------------------------------------
SELECT
    'Solution Type'                                              AS dimension_type,
    CASE
        WHEN sc.solution_count <= 1 THEN 'Single Solution'
        ELSE 'Multi Solution'
    END                                                          AS dimension_value,
    COUNT(DISTINCT CASE WHEN aa.account_renewal_arr > 0
          THEN aa.MASTER_CUSTOMER_ID END)                        AS renewal_count,
    ROUND(SUM(aa.account_renewal_arr), 2)                        AS renewal_arr,
    COUNT(DISTINCT CASE WHEN aa.account_churn_arr < 0
          THEN aa.MASTER_CUSTOMER_ID END)                        AS churn_count,
    ROUND(SUM(aa.account_churn_arr), 2)                          AS churn_arr,
    ROUND(
        (SUM(aa.account_renewal_arr) + SUM(aa.account_churn_arr))
        / NULLIF(SUM(aa.account_renewal_arr), 0), 4
    )                                                            AS renewal_rate
FROM account_arr aa
JOIN sol_count sc ON sc.MASTER_CUSTOMER_ID = aa.MASTER_CUSTOMER_ID
GROUP BY
    CASE
        WHEN sc.solution_count <= 1 THEN 'Single Solution'
        ELSE 'Multi Solution'
    END

ORDER BY dimension_type, dimension_value
;
