-- =============================================================================
-- FILE 08: OA (OPTIMIZELY ANALYTICS) ANALYSIS
-- =============================================================================
-- Description : Three result sets covering OA portfolio summary, renewal
--               performance, and monthly usage trends.
-- Parameters  : :target_quarter -- e.g. '2026-Q1'
-- Tables      : REPORTING.ARR_SST.SST_REPORT                                (SST_REPORT)
--               REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_CUSTOMER    (EXEC_DECK_CUS)
--               REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP (EXEC_DECK_PG)
--               REPORTING.GTM_ANALYTICS.EXP_CUSTOMER_ADOPTION_BRAVE         (EXP_ADOPTION)
-- Author      : CS Analytics Toolkit
-- =============================================================================


-- ---------------------------------------------------------------------------
-- QUERY 1: OA PORTFOLIO SUMMARY
-- ---------------------------------------------------------------------------
-- Grain    : Region-level summary of active OA customers and ARR
-- Source   : SST_REPORT (end-of-quarter snapshot, DAY >= 28, exclude EOL)
--            joined to EXEC_DECK_CUS for REGION
-- OA filter: UPDATED_PRODUCT_GROUP = 'Analytics'
-- ---------------------------------------------------------------------------

WITH sst_oa AS (
    SELECT
        s.MCID                                                      AS MASTER_CUSTOMER_ID,
        s.ARR                                                       AS CONTRACTED_ARR,
        s.SNAPSHOT_DATE
    FROM REPORTING.ARR_SST.SST_REPORT s
    WHERE
        s.UPDATED_PRODUCT_GROUP = 'Analytics'
        AND s.NEW_PRODUCT_SOLUTION != 'EOL'
        AND DAY(s.SNAPSHOT_DATE) >= 28
        AND TO_CHAR(s.SNAPSHOT_DATE, 'YYYY') || '-Q' ||
            QUARTER(s.SNAPSHOT_DATE)::VARCHAR = :target_quarter
),

cus_region AS (
    SELECT
        MASTER_CUSTOMER_ID,
        REGION,
        TERRITORY
    FROM REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_CUSTOMER
    WHERE DATE_YQ = :target_quarter
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY MASTER_CUSTOMER_ID ORDER BY DATE_YQ DESC
    ) = 1
)

SELECT
    COALESCE(r.REGION, 'Unknown')           AS region,
    COUNT(DISTINCT s.MASTER_CUSTOMER_ID)    AS active_customer_count,
    SUM(s.CONTRACTED_ARR)                   AS total_contracted_arr
FROM sst_oa s
LEFT JOIN cus_region r ON s.MASTER_CUSTOMER_ID = r.MASTER_CUSTOMER_ID
GROUP BY COALESCE(r.REGION, 'Unknown')

UNION ALL

SELECT
    'TOTAL'                                 AS region,
    COUNT(DISTINCT s.MASTER_CUSTOMER_ID)    AS active_customer_count,
    SUM(s.CONTRACTED_ARR)                   AS total_contracted_arr
FROM sst_oa s

ORDER BY region;


-- ---------------------------------------------------------------------------
-- QUERY 2: OA RENEWAL PERFORMANCE BY REGION AND TERRITORY
-- ---------------------------------------------------------------------------
-- Grain    : REGION x TERRITORY
-- Source   : EXEC_DECK_PG (mandatory QUALIFY dedup), filtered to Analytics
-- Metric   : Renewal Rate = (ARR_RENEWAL + ARR_CHURN) / ARR_RENEWAL
-- ---------------------------------------------------------------------------

WITH pg_oa AS (
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
    WHERE
        PRODUCT_GROUP_CLEANED = 'Analytics'
        AND DATE_YQ = :target_quarter
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY MASTER_CUSTOMER_ID, PRODUCT_GROUP_CLEANED, DATE_YM
        ORDER BY DATE_YM DESC
    ) = 1
)

SELECT
    COALESCE(REGION, 'Unknown')                 AS region,
    COALESCE(TERRITORY, 'Unknown')              AS territory,
    COUNT(DISTINCT
        CASE WHEN ARR_RENEWAL > 0 THEN MASTER_CUSTOMER_ID END
    )                                           AS renewal_count,
    COUNT(DISTINCT
        CASE WHEN ARR_CHURN < 0 THEN MASTER_CUSTOMER_ID END
    )                                           AS churn_count,
    SUM(ARR_RENEWAL)                            AS arr_renewal,
    SUM(ARR_CHURN)                              AS arr_churn,
    DIV0(
        SUM(ARR_RENEWAL) + SUM(ARR_CHURN),
        SUM(ARR_RENEWAL)
    )                                           AS renewal_rate
FROM pg_oa
GROUP BY
    COALESCE(REGION, 'Unknown'),
    COALESCE(TERRITORY, 'Unknown')
ORDER BY region, territory;


-- ---------------------------------------------------------------------------
-- QUERY 3: OA USAGE TRENDS (MONTHLY, LAST 6 MONTHS)
-- ---------------------------------------------------------------------------
-- Grain    : Month
-- Source   : EXP_CUSTOMER_ADOPTION_BRAVE for OA customers only
--            OA customers identified from SST_REPORT snapshot
-- Metric   : Average EXPERIMENTS_STARTED per month, active customer count
-- ---------------------------------------------------------------------------

WITH oa_mcids AS (
    SELECT DISTINCT MCID                                            AS MASTER_CUSTOMER_ID
    FROM REPORTING.ARR_SST.SST_REPORT
    WHERE
        UPDATED_PRODUCT_GROUP = 'Analytics'
        AND NEW_PRODUCT_SOLUTION != 'EOL'
        AND DAY(SNAPSHOT_DATE) >= 28
        AND TO_CHAR(SNAPSHOT_DATE, 'YYYY') || '-Q' ||
            QUARTER(SNAPSHOT_DATE)::VARCHAR = :target_quarter
),

adoption_filtered AS (
    SELECT
        a.MASTER_CUSTOMER_ID,
        DATE_TRUNC('MONTH', a.MONTH)            AS activity_month,
        a.EXPERIMENTS_STARTED
    FROM REPORTING.GTM_ANALYTICS.EXP_CUSTOMER_ADOPTION_BRAVE a
    INNER JOIN oa_mcids o ON a.MASTER_CUSTOMER_ID = o.MASTER_CUSTOMER_ID
    WHERE a.MONTH >= DATEADD('MONTH', -6, CURRENT_DATE)
)

SELECT
    activity_month,
    COUNT(DISTINCT MASTER_CUSTOMER_ID)      AS active_customer_count,
    AVG(EXPERIMENTS_STARTED)               AS avg_experiments_started,
    SUM(EXPERIMENTS_STARTED)               AS total_experiments_started
FROM adoption_filtered
GROUP BY activity_month
ORDER BY activity_month DESC;
