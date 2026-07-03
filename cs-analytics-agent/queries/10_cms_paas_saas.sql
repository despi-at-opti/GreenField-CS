-- =============================================================================
-- FILE 10: CMS PaaS -> SaaS MIGRATION MONITORING
-- =============================================================================
-- Description : Three result sets tracking ARR movement between CMS PaaS and
--               SaaS, renewal performance comparison, and migration customers.
-- Parameters  : :target_quarter -- e.g. '2026-Q1'
--               :snapshot_date  -- DATE, e.g. '2026-03-31'
-- Tables      : REPORTING.ARR_SST.SST_REPORT                                (SST_REPORT)
--               REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP (EXEC_DECK_PG)
--               REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_CUSTOMER    (EXEC_DECK_CUS)
-- Author      : CS Analytics Toolkit
-- =============================================================================


-- ---------------------------------------------------------------------------
-- QUERY 1: MONTHLY ARR TREND (LAST 12 MONTHS) BY PaaS vs SaaS
-- ---------------------------------------------------------------------------
-- Grain    : snapshot_month x product_type (PaaS / SaaS)
-- Source   : SST_REPORT; DAY >= 28, exclude EOL
-- Metric   : distinct MCID count, total CONTRACTED_ARR
-- ---------------------------------------------------------------------------

SELECT
    DATE_TRUNC('MONTH', SNAPSHOT_DATE)  AS snapshot_month,
    UPDATED_PRODUCT_GROUP               AS product_type,
    COUNT(DISTINCT MASTER_CUSTOMER_ID)  AS customer_count,
    SUM(CONTRACTED_ARR)                 AS total_arr
FROM REPORTING.ARR_SST.SST_REPORT
WHERE
    UPDATED_PRODUCT_GROUP IN (
        'Content Management PaaS',
        'Content Management SaaS'
    )
    AND NEW_PRODUCT_SOLUTION != 'EOL'
    AND DAY(SNAPSHOT_DATE) >= 28
    AND SNAPSHOT_DATE >= DATEADD('MONTH', -12, CURRENT_DATE)
GROUP BY
    DATE_TRUNC('MONTH', SNAPSHOT_DATE),
    UPDATED_PRODUCT_GROUP
ORDER BY snapshot_month ASC, product_type ASC;


-- ---------------------------------------------------------------------------
-- QUERY 2: RENEWAL PERFORMANCE COMPARISON (PaaS vs SaaS)
-- ---------------------------------------------------------------------------
-- Grain    : PRODUCT_GROUP_CLEANED (PaaS / SaaS)
-- Source   : EXEC_DECK_PG (mandatory QUALIFY dedup)
-- Metric   : renewal_count, churn_count, ARR sums, renewal rate
-- ---------------------------------------------------------------------------

WITH pg_cms AS (
    SELECT
        MASTER_CUSTOMER_ID,
        PRODUCT_GROUP_CLEANED,
        DATE_YQ,
        DATE_YM,
        ARR_RENEWAL,
        ARR_CHURN
    FROM REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP
    WHERE
        PRODUCT_GROUP_CLEANED IN (
            'Content Management PaaS',
            'Content Management SaaS'
        )
        AND DATE_YQ = :target_quarter
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY MASTER_CUSTOMER_ID, PRODUCT_GROUP_CLEANED, DATE_YM
        ORDER BY DATE_YM DESC
    ) = 1
)

SELECT
    PRODUCT_GROUP_CLEANED,
    COUNT(DISTINCT
        CASE WHEN ARR_RENEWAL > 0 THEN MASTER_CUSTOMER_ID END
    )                                           AS renewal_count,
    SUM(CASE WHEN ARR_RENEWAL > 0 THEN ARR_RENEWAL ELSE 0 END)
                                                AS renewal_arr,
    COUNT(DISTINCT
        CASE WHEN ARR_CHURN < 0 THEN MASTER_CUSTOMER_ID END
    )                                           AS churn_count,
    SUM(CASE WHEN ARR_CHURN < 0 THEN ARR_CHURN ELSE 0 END)
                                                AS churn_arr,
    DIV0(
        SUM(ARR_RENEWAL) + SUM(ARR_CHURN),
        SUM(ARR_RENEWAL)
    )                                           AS renewal_rate
FROM pg_cms
GROUP BY PRODUCT_GROUP_CLEANED
ORDER BY PRODUCT_GROUP_CLEANED;


-- ---------------------------------------------------------------------------
-- QUERY 3: MIGRATION CUSTOMERS
-- ---------------------------------------------------------------------------
-- Grain    : One row per MCID that has BOTH PaaS and SaaS active at :snapshot_date
-- Source   : SST_REPORT at :snapshot_date
--            joined to EXEC_DECK_CUS for account metadata
-- Metric   : paas_arr, saas_arr, total_arr per account
-- ---------------------------------------------------------------------------

WITH snapshot_cms AS (
    SELECT
        MASTER_CUSTOMER_ID,
        UPDATED_PRODUCT_GROUP,
        SUM(CONTRACTED_ARR) AS product_arr
    FROM REPORTING.ARR_SST.SST_REPORT
    WHERE
        SNAPSHOT_DATE = :snapshot_date
        AND UPDATED_PRODUCT_GROUP IN (
            'Content Management PaaS',
            'Content Management SaaS'
        )
        AND NEW_PRODUCT_SOLUTION != 'EOL'
    GROUP BY MASTER_CUSTOMER_ID, UPDATED_PRODUCT_GROUP
),

paas_accounts AS (
    SELECT MASTER_CUSTOMER_ID, product_arr AS paas_arr
    FROM snapshot_cms
    WHERE UPDATED_PRODUCT_GROUP = 'Content Management PaaS'
),

saas_accounts AS (
    SELECT MASTER_CUSTOMER_ID, product_arr AS saas_arr
    FROM snapshot_cms
    WHERE UPDATED_PRODUCT_GROUP = 'Content Management SaaS'
),

migration_mcids AS (
    SELECT
        p.MASTER_CUSTOMER_ID,
        p.paas_arr,
        s.saas_arr,
        p.paas_arr + s.saas_arr AS total_arr
    FROM paas_accounts p
    INNER JOIN saas_accounts s ON p.MASTER_CUSTOMER_ID = s.MASTER_CUSTOMER_ID
),

cus_meta AS (
    SELECT
        MASTER_CUSTOMER_ID,
        ACCOUNT_NAME,
        PRIMARY_CSM,
        REGION
    FROM REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_CUSTOMER
    WHERE DATE_YQ = :target_quarter
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY MASTER_CUSTOMER_ID ORDER BY DATE_YQ DESC
    ) = 1
)

SELECT
    c.ACCOUNT_NAME,
    c.PRIMARY_CSM,
    c.REGION,
    m.MASTER_CUSTOMER_ID,
    m.paas_arr,
    m.saas_arr,
    m.total_arr
FROM migration_mcids m
LEFT JOIN cus_meta c ON m.MASTER_CUSTOMER_ID = c.MASTER_CUSTOMER_ID
ORDER BY m.total_arr DESC;
