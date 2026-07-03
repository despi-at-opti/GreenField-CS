-- =============================================================================
-- FILE 09: EO (EXPERIMENTATION OPTIMIZATION) DEEP DIVE
-- =============================================================================
-- Description : Four result sets for deep EO analysis: regional renewals,
--               Opal attach correlation, high/low tester renewal rates,
--               and next product probability from Web Experimentation.
-- Parameters  : :target_quarter  -- e.g. '2026-Q1'
--               :start_snapshot  -- DATE, e.g. '2025-09-30'
--               :end_snapshot    -- DATE, e.g. '2026-03-31'
-- Tables      : REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP (EXEC_DECK_PG)
--               REPORTING.OPTI_APPLICATION.EXPERIMENT_METRICS                  (EXPERIMENT_METRICS)
--               REPORTING.OPTI_APPLICATION.OA_CUSTOMER_DETAIL                  (OA_CUSTOMER_DETAIL)
--               REPORTING.ARR_SST.SST_REPORT                                   (SST_REPORT)
-- EO Products : Analytics, Feature Experimentation, Web Experimentation,
--               Experimentation Platform, Experimentation Addons,
--               Personalization, Segmentation
-- Author      : CS Analytics Toolkit
-- =============================================================================


-- ---------------------------------------------------------------------------
-- QUERY 1: EO RENEWALS BY REGION (EMEA vs NAM) WITH QoQ COMPARISON
-- ---------------------------------------------------------------------------
-- Grain    : Period (Current/Prior) x REGION
-- Source   : EXEC_DECK_PG (mandatory QUALIFY dedup)
-- Logic    : Current quarter = :target_quarter
--            Prior quarter derived automatically
--            Renewal Rate = (ARR_RENEWAL + ARR_CHURN) / ARR_RENEWAL
-- ---------------------------------------------------------------------------

WITH quarter_periods AS (
    -- Derive prior quarter string from :target_quarter
    SELECT
        :target_quarter AS current_quarter,
        CASE
            WHEN RIGHT(:target_quarter, 2) = 'Q1'
                THEN (LEFT(:target_quarter, 4)::INT - 1)::VARCHAR || '-Q4'
            ELSE
                LEFT(:target_quarter, 4) || '-Q' ||
                (RIGHT(:target_quarter, 1)::INT - 1)::VARCHAR
        END AS prior_quarter
),

pg_eo_deduped AS (
    -- Deduplicate EXEC_DECK_PG for EO products across current and prior quarters
    SELECT
        MASTER_CUSTOMER_ID,
        PRODUCT_GROUP_CLEANED,
        DATE_YQ,
        DATE_YM,
        ARR_RENEWAL,
        ARR_CHURN,
        REGION,
        TERRITORY
    FROM REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP
    WHERE PRODUCT_GROUP_CLEANED IN (
        'Analytics',
        'Feature Experimentation',
        'Web Experimentation',
        'Experimentation Platform',
        'Experimentation Addons',
        'Personalization',
        'Segmentation'
    )
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY MASTER_CUSTOMER_ID, PRODUCT_GROUP_CLEANED, DATE_YM
        ORDER BY DATE_YM DESC
    ) = 1
),

current_regional AS (
    SELECT
        'Current'                           AS period,
        p.current_quarter                   AS date_yq,
        COALESCE(d.REGION, 'Unknown')       AS region,
        COUNT(DISTINCT
            CASE WHEN d.ARR_RENEWAL > 0 THEN d.MASTER_CUSTOMER_ID END
        )                                   AS renewal_count,
        SUM(d.ARR_RENEWAL)                  AS renewal_arr,
        SUM(d.ARR_CHURN)                    AS churn_arr,
        DIV0(
            SUM(d.ARR_RENEWAL) + SUM(d.ARR_CHURN),
            SUM(d.ARR_RENEWAL)
        )                                   AS renewal_rate
    FROM pg_eo_deduped d
    CROSS JOIN quarter_periods p
    WHERE d.DATE_YQ = p.current_quarter
    GROUP BY p.current_quarter, COALESCE(d.REGION, 'Unknown')
),

prior_regional AS (
    SELECT
        'Prior'                             AS period,
        p.prior_quarter                     AS date_yq,
        COALESCE(d.REGION, 'Unknown')       AS region,
        COUNT(DISTINCT
            CASE WHEN d.ARR_RENEWAL > 0 THEN d.MASTER_CUSTOMER_ID END
        )                                   AS renewal_count,
        SUM(d.ARR_RENEWAL)                  AS renewal_arr,
        SUM(d.ARR_CHURN)                    AS churn_arr,
        DIV0(
            SUM(d.ARR_RENEWAL) + SUM(d.ARR_CHURN),
            SUM(d.ARR_RENEWAL)
        )                                   AS renewal_rate
    FROM pg_eo_deduped d
    CROSS JOIN quarter_periods p
    WHERE d.DATE_YQ = p.prior_quarter
    GROUP BY p.prior_quarter, COALESCE(d.REGION, 'Unknown')
)

SELECT
    c.period,
    c.date_yq,
    c.region,
    c.renewal_count,
    c.renewal_arr,
    c.churn_arr,
    c.renewal_rate,
    -- QoQ delta vs same region in prior quarter
    c.renewal_rate - pr.renewal_rate        AS renewal_rate_qoq_delta,
    c.renewal_arr  - pr.renewal_arr         AS arr_renewal_qoq_delta
FROM current_regional c
LEFT JOIN prior_regional pr ON c.region = pr.region

UNION ALL

SELECT
    pr.period,
    pr.date_yq,
    pr.region,
    pr.renewal_count,
    pr.renewal_arr,
    pr.churn_arr,
    pr.renewal_rate,
    NULL AS renewal_rate_qoq_delta,
    NULL AS arr_renewal_qoq_delta
FROM prior_regional pr

ORDER BY period DESC, region;


-- ---------------------------------------------------------------------------
-- QUERY 2: OPAL ATTACH CORRELATION WITH EO RENEWAL RATES
-- ---------------------------------------------------------------------------
-- Grain    : OPAL_ATTACH flag (Yes / No)
-- Source   : EXEC_DECK_PG (QUALIFY dedup)
-- Logic    : For each EO customer in :target_quarter, flag whether they also
--            have an Opal row in the same quarter.
--            Shows whether Opal-attached EO customers renew at a higher rate.
-- NOTE     : Opal attach derived from EXEC_DECK_PG rows, NOT RENEWAL_OPP.IS_OPAL
-- ---------------------------------------------------------------------------

WITH pg_deduped AS (
    SELECT
        MASTER_CUSTOMER_ID,
        PRODUCT_GROUP_CLEANED,
        DATE_YQ,
        DATE_YM,
        ARR_RENEWAL,
        ARR_CHURN
    FROM REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP
    WHERE DATE_YQ = :target_quarter
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY MASTER_CUSTOMER_ID, PRODUCT_GROUP_CLEANED, DATE_YM
        ORDER BY DATE_YM DESC
    ) = 1
),

eo_accounts AS (
    -- EO customers in the target quarter
    SELECT DISTINCT MASTER_CUSTOMER_ID
    FROM pg_deduped
    WHERE PRODUCT_GROUP_CLEANED IN (
        'Analytics',
        'Feature Experimentation',
        'Web Experimentation',
        'Experimentation Platform',
        'Experimentation Addons',
        'Personalization',
        'Segmentation'
    )
),

opal_flag AS (
    -- Flag each EO MCID as Opal-attached or not
    SELECT
        e.MASTER_CUSTOMER_ID,
        IFF(COUNT(o.MASTER_CUSTOMER_ID) > 0, 'Yes', 'No') AS opal_attach
    FROM eo_accounts e
    LEFT JOIN pg_deduped o
        ON  e.MASTER_CUSTOMER_ID = o.MASTER_CUSTOMER_ID
        AND o.PRODUCT_GROUP_CLEANED = 'Opal'
    GROUP BY e.MASTER_CUSTOMER_ID
),

eo_metrics AS (
    -- EO renewal metrics aggregated per MCID
    SELECT
        MASTER_CUSTOMER_ID,
        SUM(ARR_RENEWAL) AS arr_renewal,
        SUM(ARR_CHURN)   AS arr_churn
    FROM pg_deduped
    WHERE PRODUCT_GROUP_CLEANED IN (
        'Analytics',
        'Feature Experimentation',
        'Web Experimentation',
        'Experimentation Platform',
        'Experimentation Addons',
        'Personalization',
        'Segmentation'
    )
    GROUP BY MASTER_CUSTOMER_ID
)

SELECT
    f.opal_attach,
    COUNT(DISTINCT m.MASTER_CUSTOMER_ID)    AS renewal_count,
    SUM(m.arr_renewal)                      AS renewal_arr,
    SUM(m.arr_churn)                        AS churn_arr,
    DIV0(
        SUM(m.arr_renewal) + SUM(m.arr_churn),
        SUM(m.arr_renewal)
    )                                       AS renewal_rate
FROM opal_flag f
INNER JOIN eo_metrics m ON f.MASTER_CUSTOMER_ID = m.MASTER_CUSTOMER_ID
GROUP BY f.opal_attach
ORDER BY f.opal_attach DESC;


-- ---------------------------------------------------------------------------
-- QUERY 3: HIGH TESTER vs LOW TESTER RENEWAL RATE
-- ---------------------------------------------------------------------------
-- Grain    : tester_type (High / Low)
-- Source   : EXEC_DECK_PG (EO customers, :target_quarter)
--            EXPERIMENT_METRICS (via OA_CUSTOMER_DETAIL for MCID join)
-- Logic    : Avg experiments per month per MCID from EXPERIMENT_METRICS
--            High Tester: avg >= 9 per month
--            Low Tester : avg <  9 per month
-- ---------------------------------------------------------------------------

WITH pg_eo AS (
    -- EO accounts with renewal metrics, deduped
    SELECT
        MASTER_CUSTOMER_ID,
        DATE_YQ,
        SUM(ARR_RENEWAL) AS arr_renewal,
        SUM(ARR_CHURN)   AS arr_churn
    FROM REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP
    WHERE
        PRODUCT_GROUP_CLEANED IN (
            'Analytics',
            'Feature Experimentation',
            'Web Experimentation',
            'Experimentation Platform',
            'Experimentation Addons',
            'Personalization',
            'Segmentation'
        )
        AND DATE_YQ = :target_quarter
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY MASTER_CUSTOMER_ID, PRODUCT_GROUP_CLEANED, DATE_YM
        ORDER BY DATE_YM DESC
    ) = 1
    -- Re-aggregate after dedup
),

pg_eo_agg AS (
    SELECT
        MASTER_CUSTOMER_ID,
        SUM(arr_renewal) AS arr_renewal,
        SUM(arr_churn)   AS arr_churn
    FROM pg_eo
    GROUP BY MASTER_CUSTOMER_ID
),

-- Map MCID to application-level account ID via OA_CUSTOMER_DETAIL
oa_map AS (
    SELECT
        MASTER_CUSTOMER_ID,
        ACCOUNT_ID      -- application-level identifier used in EXPERIMENT_METRICS
    FROM REPORTING.OPTI_APPLICATION.OA_CUSTOMER_DETAIL
),

-- Calculate avg experiments per month per MCID over the last 12 months
exp_avg AS (
    SELECT
        m.MASTER_CUSTOMER_ID,
        AVG(e.EXPERIMENTS_COUNT)            AS avg_experiments_per_month
    FROM REPORTING.OPTI_APPLICATION.EXPERIMENT_METRICS e
    INNER JOIN oa_map m ON e.ACCOUNT_ID = m.ACCOUNT_ID
    WHERE e.METRIC_MONTH >= DATEADD('MONTH', -12, CURRENT_DATE)
    GROUP BY m.MASTER_CUSTOMER_ID
),

-- Classify each MCID as High or Low Tester
tester_classification AS (
    SELECT
        MASTER_CUSTOMER_ID,
        avg_experiments_per_month,
        IFF(avg_experiments_per_month >= 9, 'High Tester', 'Low Tester') AS tester_type
    FROM exp_avg
)

SELECT
    COALESCE(t.tester_type, 'No Usage Data')    AS tester_type,
    COUNT(DISTINCT p.MASTER_CUSTOMER_ID)         AS renewal_count,
    SUM(p.arr_renewal)                           AS renewal_arr,
    SUM(p.arr_churn)                             AS churn_arr,
    DIV0(
        SUM(p.arr_renewal) + SUM(p.arr_churn),
        SUM(p.arr_renewal)
    )                                            AS renewal_rate
FROM pg_eo_agg p
LEFT JOIN tester_classification t ON p.MASTER_CUSTOMER_ID = t.MASTER_CUSTOMER_ID
GROUP BY COALESCE(t.tester_type, 'No Usage Data')
ORDER BY tester_type;


-- ---------------------------------------------------------------------------
-- QUERY 4: NEXT PRODUCT PROBABILITY (Web Experimentation -> X)
-- ---------------------------------------------------------------------------
-- Grain    : next_product (candidate product added after Web Experimentation)
-- Source   : SST_REPORT at :start_snapshot and :end_snapshot dates
-- Logic    : Identify MCIDs with Web Experimentation at :start_snapshot
--            but NOT product X; check if they added product X by :end_snapshot
--            Conversion rate = customers_who_added / customers_who_had_webex_at_start
-- NOTE     : EOL and Opal products are included for completeness but can be
--            filtered downstream; EOL rows excluded via NEW_PRODUCT_SOLUTION != 'EOL'
-- ---------------------------------------------------------------------------

WITH webex_at_start AS (
    -- MCIDs that had Web Experimentation at the start snapshot
    SELECT DISTINCT MASTER_CUSTOMER_ID
    FROM REPORTING.ARR_SST.SST_REPORT
    WHERE
        SNAPSHOT_DATE = :start_snapshot
        AND DAY(SNAPSHOT_DATE) >= 28
        AND NEW_PRODUCT_SOLUTION != 'EOL'
        AND UPDATED_PRODUCT_GROUP = 'Web Experimentation'
),

all_products_at_start AS (
    -- All product groups each Web Experimentation MCID had at start snapshot
    SELECT DISTINCT
        s.MASTER_CUSTOMER_ID,
        s.UPDATED_PRODUCT_GROUP
    FROM REPORTING.ARR_SST.SST_REPORT s
    INNER JOIN webex_at_start w ON s.MASTER_CUSTOMER_ID = w.MASTER_CUSTOMER_ID
    WHERE
        s.SNAPSHOT_DATE = :start_snapshot
        AND s.NEW_PRODUCT_SOLUTION != 'EOL'
),

all_products_at_end AS (
    -- All product groups each Web Experimentation MCID has at end snapshot
    SELECT DISTINCT
        s.MASTER_CUSTOMER_ID,
        s.UPDATED_PRODUCT_GROUP
    FROM REPORTING.ARR_SST.SST_REPORT s
    INNER JOIN webex_at_start w ON s.MASTER_CUSTOMER_ID = w.MASTER_CUSTOMER_ID
    WHERE
        s.SNAPSHOT_DATE = :end_snapshot
        AND s.NEW_PRODUCT_SOLUTION != 'EOL'
),

-- For each candidate next product, compute the conversion funnel
candidate_products AS (
    -- Distinct products present at end snapshot (excluding Web Experimentation itself)
    SELECT DISTINCT UPDATED_PRODUCT_GROUP AS next_product
    FROM all_products_at_end
    WHERE UPDATED_PRODUCT_GROUP != 'Web Experimentation'
),

funnel AS (
    SELECT
        cp.next_product,
        -- Denominator: Web Experimentation MCIDs that did NOT have this product at start
        COUNT(DISTINCT CASE
            WHEN st.MASTER_CUSTOMER_ID IS NULL THEN w.MASTER_CUSTOMER_ID
        END)                                        AS customers_who_had_webex_at_start,
        -- Numerator: those MCIDs that added the product by end snapshot
        COUNT(DISTINCT CASE
            WHEN st.MASTER_CUSTOMER_ID IS NULL
             AND en.MASTER_CUSTOMER_ID IS NOT NULL
            THEN w.MASTER_CUSTOMER_ID
        END)                                        AS customers_who_added_next_product
    FROM candidate_products cp
    CROSS JOIN webex_at_start w
    -- Did the MCID already have this product at start?
    LEFT JOIN all_products_at_start st
        ON  w.MASTER_CUSTOMER_ID = st.MASTER_CUSTOMER_ID
        AND st.UPDATED_PRODUCT_GROUP = cp.next_product
    -- Did the MCID gain this product by end?
    LEFT JOIN all_products_at_end en
        ON  w.MASTER_CUSTOMER_ID = en.MASTER_CUSTOMER_ID
        AND en.UPDATED_PRODUCT_GROUP = cp.next_product
    GROUP BY cp.next_product
)

SELECT
    next_product,
    customers_who_had_webex_at_start,
    customers_who_added_next_product,
    DIV0(
        customers_who_added_next_product * 100.0,
        customers_who_had_webex_at_start
    )                                               AS conversion_rate_pct
FROM funnel
WHERE customers_who_had_webex_at_start > 0
ORDER BY conversion_rate_pct DESC;
