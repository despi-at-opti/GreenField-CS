-- =============================================================================
-- FILE 07: OPAL ANALYSIS
-- =============================================================================
-- Description : Three result sets covering Opal pipeline, attach rate,
--               and renewal performance.
-- Parameters  : :target_quarter  -- e.g. '2026-Q1'
--               :pipeline_quarter -- e.g. '2026-Q1' (for pipeline stage filter)
-- Tables      : REPORTING.GTM_ANALYTICS.RENEWAL_OPPORTUNITY         (RENEWAL_OPP)
--               REPORTING.ARR_SST.SST_REPORT                        (SST_REPORT)
--               REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_CUSTOMER (EXEC_DECK_CUS)
--               REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP (EXEC_DECK_PG)
-- Grain       : See individual query headers
-- Author      : CS Analytics Toolkit
-- =============================================================================


-- ---------------------------------------------------------------------------
-- QUERY 1: OPAL PIPELINE
-- ---------------------------------------------------------------------------
-- Grain    : OPPORTUNITY_STAGE (pipeline stage)
-- Source   : RENEWAL_OPP, filtered to Opal product line
-- Rule     : Always aggregate to MAX(RENEWAL_FINAL_AMOUNT_USD) per MCID + OPPORTUNITY_ID
--            before rolling up to stage level, to avoid double-counting
-- Parameter: :pipeline_quarter (DATE_YQ = :pipeline_quarter)
-- ---------------------------------------------------------------------------

WITH opal_opps AS (
    SELECT
        MASTER_CUSTOMER_ID,
        OPPORTUNITY_ID,
        OPPORTUNITY_STAGE,
        -- Deduplicate to one row per MCID + opportunity, taking max ARR
        MAX(RENEWAL_FINAL_AMOUNT_USD) AS opp_arr
    FROM REPORTING.GTM_ANALYTICS.RENEWAL_OPPORTUNITY
    WHERE
        LOWER(PRODUCT_LINE) = 'opal'
        AND DATE_YQ = :pipeline_quarter
    GROUP BY
        MASTER_CUSTOMER_ID,
        OPPORTUNITY_ID,
        OPPORTUNITY_STAGE
)

SELECT
    OPPORTUNITY_STAGE                   AS pipeline_stage,
    COUNT(DISTINCT MASTER_CUSTOMER_ID)  AS account_count,
    COUNT(DISTINCT OPPORTUNITY_ID)      AS opportunity_count,
    SUM(opp_arr)                        AS total_pipeline_arr
FROM opal_opps
GROUP BY OPPORTUNITY_STAGE
ORDER BY total_pipeline_arr DESC;


-- ---------------------------------------------------------------------------
-- QUERY 2: OPAL ATTACH RATE
-- ---------------------------------------------------------------------------
-- Grain    : Overall attach rate + breakdown by REGION
-- Source   : SST_REPORT for snapshot month within :target_quarter (DAY >= 28),
--            joined to EXEC_DECK_CUS for REGION
-- Logic    :
--   Denominator = distinct MCIDs with ANY EO product in the snapshot
--   Numerator   = distinct MCIDs with BOTH an EO product AND Opal
--   Attach rate = numerator / denominator
-- EO product list: Analytics, Feature Experimentation, Web Experimentation,
--   Experimentation Platform, Experimentation Addons, Personalization, Segmentation
-- NOTE     : NEVER use RENEWAL_OPP.IS_OPAL for attach rate logic
-- ---------------------------------------------------------------------------

WITH snapshot_base AS (
    -- Latest end-of-month snapshot within the target quarter; exclude EOL
    SELECT
        MASTER_CUSTOMER_ID,
        UPDATED_PRODUCT_GROUP,
        SNAPSHOT_DATE,
        CONTRACTED_ARR
    FROM REPORTING.ARR_SST.SST_REPORT
    WHERE
        DAY(SNAPSHOT_DATE) >= 28
        AND NEW_PRODUCT_SOLUTION != 'EOL'
        AND TO_CHAR(SNAPSHOT_DATE, 'YYYY') || '-Q' ||
            QUARTER(SNAPSHOT_DATE)::VARCHAR = :target_quarter
),

eo_customers AS (
    -- All MCIDs that carry at least one EO-family product
    SELECT DISTINCT MASTER_CUSTOMER_ID
    FROM snapshot_base
    WHERE UPDATED_PRODUCT_GROUP IN (
        'Analytics',
        'Feature Experimentation',
        'Web Experimentation',
        'Experimentation Platform',
        'Experimentation Addons',
        'Personalization',
        'Segmentation'
    )
),

opal_customers AS (
    -- All MCIDs that carry Opal
    SELECT DISTINCT MASTER_CUSTOMER_ID
    FROM snapshot_base
    WHERE UPDATED_PRODUCT_GROUP = 'Opal'
),

eo_with_opal AS (
    -- MCIDs that have BOTH an EO product and Opal (the attached cohort)
    SELECT ec.MASTER_CUSTOMER_ID
    FROM eo_customers ec
    INNER JOIN opal_customers oc
        ON ec.MASTER_CUSTOMER_ID = oc.MASTER_CUSTOMER_ID
),

-- Pull REGION from EXEC_DECK_CUS for the target quarter
cus_region AS (
    SELECT
        MASTER_CUSTOMER_ID,
        REGION
    FROM REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_CUSTOMER
    WHERE DATE_YQ = :target_quarter
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY MASTER_CUSTOMER_ID ORDER BY DATE_YQ DESC
    ) = 1
),

-- Overall attach rate (single summary row)
overall AS (
    SELECT
        'ALL'                                       AS region,
        COUNT(DISTINCT e.MASTER_CUSTOMER_ID)        AS eo_customer_count,
        COUNT(DISTINCT w.MASTER_CUSTOMER_ID)        AS opal_attached_count,
        DIV0(
            COUNT(DISTINCT w.MASTER_CUSTOMER_ID),
            COUNT(DISTINCT e.MASTER_CUSTOMER_ID)
        )                                           AS opal_attach_rate
    FROM eo_customers e
    LEFT JOIN eo_with_opal w
        ON e.MASTER_CUSTOMER_ID = w.MASTER_CUSTOMER_ID
),

-- Regional attach rate breakdown
regional AS (
    SELECT
        COALESCE(r.REGION, 'Unknown')               AS region,
        COUNT(DISTINCT e.MASTER_CUSTOMER_ID)        AS eo_customer_count,
        COUNT(DISTINCT w.MASTER_CUSTOMER_ID)        AS opal_attached_count,
        DIV0(
            COUNT(DISTINCT w.MASTER_CUSTOMER_ID),
            COUNT(DISTINCT e.MASTER_CUSTOMER_ID)
        )                                           AS opal_attach_rate
    FROM eo_customers e
    LEFT JOIN eo_with_opal w
        ON e.MASTER_CUSTOMER_ID = w.MASTER_CUSTOMER_ID
    LEFT JOIN cus_region r
        ON e.MASTER_CUSTOMER_ID = r.MASTER_CUSTOMER_ID
    GROUP BY COALESCE(r.REGION, 'Unknown')
)

SELECT * FROM overall
UNION ALL
SELECT * FROM regional
ORDER BY region;


-- ---------------------------------------------------------------------------
-- QUERY 3: OPAL RENEWALS WITH QoQ COMPARISON
-- ---------------------------------------------------------------------------
-- Grain    : Quarter-level summary for Opal product group
-- Source   : EXEC_DECK_PG (mandatory QUALIFY dedup applied)
-- Logic    : Renewal Rate = (ARR_RENEWAL + ARR_CHURN) / ARR_RENEWAL
--            Prior quarter is derived automatically from :target_quarter
-- ---------------------------------------------------------------------------

WITH pg_deduped AS (
    -- Deduplicate EXEC_DECK_PG to one row per MCID x product group x month
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
    WHERE PRODUCT_GROUP_CLEANED = 'Opal'
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY MASTER_CUSTOMER_ID, PRODUCT_GROUP_CLEANED, DATE_YM
        ORDER BY DATE_YM DESC
    ) = 1
),

-- Derive prior quarter string from :target_quarter (e.g. '2026-Q1' -> '2025-Q4')
quarter_periods AS (
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

current_q AS (
    SELECT
        'Current'                           AS period,
        p.current_quarter                   AS date_yq,
        COUNT(DISTINCT
            CASE WHEN d.ARR_RENEWAL > 0 THEN d.MASTER_CUSTOMER_ID END
        )                                   AS renewal_count,
        SUM(d.ARR_RENEWAL)                  AS arr_renewal,
        SUM(d.ARR_CHURN)                    AS arr_churn,
        DIV0(
            SUM(d.ARR_RENEWAL) + SUM(d.ARR_CHURN),
            SUM(d.ARR_RENEWAL)
        )                                   AS renewal_rate
    FROM pg_deduped d
    CROSS JOIN quarter_periods p
    WHERE d.DATE_YQ = p.current_quarter
    GROUP BY p.current_quarter
),

prior_q AS (
    SELECT
        'Prior'                             AS period,
        p.prior_quarter                     AS date_yq,
        COUNT(DISTINCT
            CASE WHEN d.ARR_RENEWAL > 0 THEN d.MASTER_CUSTOMER_ID END
        )                                   AS renewal_count,
        SUM(d.ARR_RENEWAL)                  AS arr_renewal,
        SUM(d.ARR_CHURN)                    AS arr_churn,
        DIV0(
            SUM(d.ARR_RENEWAL) + SUM(d.ARR_CHURN),
            SUM(d.ARR_RENEWAL)
        )                                   AS renewal_rate
    FROM pg_deduped d
    CROSS JOIN quarter_periods p
    WHERE d.DATE_YQ = p.prior_quarter
    GROUP BY p.prior_quarter
)

-- Current quarter row with QoQ delta columns
SELECT
    c.period,
    c.date_yq,
    c.renewal_count,
    c.arr_renewal,
    c.arr_churn,
    c.renewal_rate,
    c.renewal_rate - pr.renewal_rate       AS renewal_rate_qoq_delta,
    c.arr_renewal  - pr.arr_renewal        AS arr_renewal_qoq_delta
FROM current_q c
CROSS JOIN prior_q pr

UNION ALL

-- Prior quarter row (deltas are NULL for the baseline period)
SELECT
    pr.period,
    pr.date_yq,
    pr.renewal_count,
    pr.arr_renewal,
    pr.arr_churn,
    pr.renewal_rate,
    NULL AS renewal_rate_qoq_delta,
    NULL AS arr_renewal_qoq_delta
FROM prior_q pr

ORDER BY period DESC;
