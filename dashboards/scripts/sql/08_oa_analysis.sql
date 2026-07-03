-- =============================================================================
-- FILE 08: OA (OPTIMIZELY ANALYTICS) ANALYSIS — updated 2026-06
-- =============================================================================
-- Description : Three result sets for OA portfolio analysis:
--               customer counts by region, renewal performance by region,
--               and monthly usage trends.
-- Parameters  : :target_quarter  e.g. '2026-Q2'
-- Tables      : REPORTING.OPTI_APPLICATION.OA_CUSTOMER_DETAIL
--               REPORTING.SALESFORCE.RAW_OPPORTUNITY_REPORT
--               REPORTING.GTM_ANALYTICS.EXP_CUSTOMER_ADOPTION_BRAVE
-- Section tags: "customers"  → region, active_customer_count
--               "regional"   → region, renewal_arr, churn_arr, renewal_rate
--               "trend"      → activity_month, active_customer_count,
--                              avg_experiments_started, total_experiments_started
-- Notes:
--   • OA_CUSTOMER_DETAIL.SALESFORCE_ACCOUNT_ID joins to RAW_OPP.ACCOUNT_ID
--   • RAW_OPP fiscal format is 'YYYY N' e.g. '2026 2'; derive with:
--       LEFT(:target_quarter,4) || ' ' || RIGHT(:target_quarter,1)
--   • EXP_CUSTOMER_ADOPTION_BRAVE uses YEAR_MONTH (VARCHAR 'YYYY-MM'), not a DATE col
--   • Renewal ARR in "regional" is account-level (all products), not OA-specific ARR
--   • UNION ALL is blocked — run each query separately and merge in Python
-- =============================================================================


-- ---------------------------------------------------------------------------
-- QUERY 1: ACTIVE OA CUSTOMER COUNT BY REGION
-- ---------------------------------------------------------------------------
-- Section: "customers"
-- ---------------------------------------------------------------------------

SELECT
    CASE
        WHEN BILLING_COUNTRY IN (
            'United States','Canada','Mexico'
        ) THEN 'NA'
        WHEN BILLING_COUNTRY IN (
            'United Kingdom','Germany','France','Netherlands','Sweden',
            'Denmark','Finland','Norway','Spain','Italy','Ireland','Belgium',
            'Austria','Switzerland','Poland','Portugal','Czech Republic',
            'Romania','Hungary','Turkey','Israel','South Africa','UAE',
            'United Arab Emirates','Saudi Arabia'
        ) THEN 'EMEA'
        WHEN BILLING_COUNTRY IN (
            'Australia','Japan','New Zealand','Singapore','India',
            'Hong Kong','South Korea','China','Malaysia','Philippines',
            'Indonesia','Thailand'
        ) THEN 'APJ'
        ELSE 'Other'
    END                                     AS region,
    COUNT(*)                                AS active_customer_count
FROM REPORTING.OPTI_APPLICATION.OA_CUSTOMER_DETAIL
WHERE IS_ACTIVE = TRUE
GROUP BY 1
ORDER BY active_customer_count DESC;


-- ---------------------------------------------------------------------------
-- QUERY 2: OA RENEWAL PERFORMANCE BY REGION (account-level ARR)
-- ---------------------------------------------------------------------------
-- Section: "regional"
-- Warning: ARR is account-level (all products), not OA-specific
-- ---------------------------------------------------------------------------

WITH oa_accounts AS (
    SELECT
        SALESFORCE_ACCOUNT_ID,
        CASE
            WHEN BILLING_COUNTRY IN (
                'United States','Canada','Mexico'
            ) THEN 'NA'
            WHEN BILLING_COUNTRY IN (
                'United Kingdom','Germany','France','Netherlands','Sweden',
                'Denmark','Finland','Norway','Spain','Italy','Ireland','Belgium',
                'Austria','Switzerland','Poland','Portugal','Czech Republic',
                'Romania','Hungary','Turkey','Israel','South Africa','UAE',
                'United Arab Emirates','Saudi Arabia'
            ) THEN 'EMEA'
            WHEN BILLING_COUNTRY IN (
                'Australia','Japan','New Zealand','Singapore','India',
                'Hong Kong','South Korea','China','Malaysia','Philippines',
                'Indonesia','Thailand'
            ) THEN 'APJ'
            ELSE 'Other'
        END AS region
    FROM REPORTING.OPTI_APPLICATION.OA_CUSTOMER_DETAIL
    WHERE IS_ACTIVE = TRUE
)

SELECT
    a.region,
    SUM(CASE WHEN r.STAGE_NAME = 'Closed Won'
             AND r.FISCAL = LEFT(:target_quarter, 4) || ' ' || RIGHT(:target_quarter, 1)
        THEN COALESCE(r.RENEWAL_FINAL_AMOUNT_C, 0) ELSE 0 END)      AS renewal_arr,
    -SUM(CASE WHEN r.STAGE_NAME = 'Closed Lost'
              AND r.FISCAL = LEFT(:target_quarter, 4) || ' ' || RIGHT(:target_quarter, 1)
        THEN ABS(COALESCE(r.RENEWAL_FINAL_AMOUNT_C, 0)) ELSE 0 END)  AS churn_arr,
    DIV0(
        SUM(CASE WHEN r.STAGE_NAME = 'Closed Won'
                 AND r.FISCAL = LEFT(:target_quarter, 4) || ' ' || RIGHT(:target_quarter, 1)
            THEN COALESCE(r.RENEWAL_FINAL_AMOUNT_C, 0) ELSE 0 END)
        - SUM(CASE WHEN r.STAGE_NAME = 'Closed Lost'
                   AND r.FISCAL = LEFT(:target_quarter, 4) || ' ' || RIGHT(:target_quarter, 1)
              THEN ABS(COALESCE(r.RENEWAL_FINAL_AMOUNT_C, 0)) ELSE 0 END),
        SUM(CASE WHEN r.STAGE_NAME = 'Closed Won'
                 AND r.FISCAL = LEFT(:target_quarter, 4) || ' ' || RIGHT(:target_quarter, 1)
            THEN COALESCE(r.RENEWAL_FINAL_AMOUNT_C, 0) ELSE 0 END)
    )                                                                 AS renewal_rate
FROM oa_accounts a
JOIN REPORTING.SALESFORCE.RAW_OPPORTUNITY_REPORT r
    ON a.SALESFORCE_ACCOUNT_ID = r.ACCOUNT_ID
GROUP BY a.region
HAVING renewal_arr > 0
ORDER BY renewal_arr DESC;


-- ---------------------------------------------------------------------------
-- QUERY 3: OA USAGE TRENDS (last 12 months)
-- ---------------------------------------------------------------------------
-- Section: "trend"
-- ---------------------------------------------------------------------------

WITH oa_mcids AS (
    SELECT DISTINCT MASTER_CUSTOMER_ID
    FROM REPORTING.OPTI_APPLICATION.OA_CUSTOMER_DETAIL
    WHERE IS_ACTIVE = TRUE
)

SELECT
    a.YEAR_MONTH                                AS activity_month,
    COUNT(DISTINCT a.MASTER_CUSTOMER_ID)        AS active_customer_count,
    AVG(a.EXPERIMENTS_STARTED)                  AS avg_experiments_started,
    SUM(a.EXPERIMENTS_STARTED)                  AS total_experiments_started
FROM REPORTING.GTM_ANALYTICS.EXP_CUSTOMER_ADOPTION_BRAVE a
INNER JOIN oa_mcids o ON a.MASTER_CUSTOMER_ID = o.MASTER_CUSTOMER_ID
WHERE a.YEAR_MONTH >= TO_CHAR(DATEADD('MONTH', -12, CURRENT_DATE), 'YYYY-MM')
GROUP BY a.YEAR_MONTH
ORDER BY a.YEAR_MONTH DESC;
