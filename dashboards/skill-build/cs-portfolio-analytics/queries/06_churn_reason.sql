-- =============================================================================
-- 06_churn_reason.sql
-- Churn Reason Analysis
-- =============================================================================
-- Description : Analyses churn reasons from Salesforce Closed-Lost opportunities
--               matched to customer ARR data from EXEC_DECK_CUS.
--               Returns both a SUMMARY rollup and a DETAIL account-level view.
--
-- Sources:
--   RAW_OPP        REPORTING.SALESFORCE.RAW_OPPORTUNITY_REPORT
--   EXEC_DECK_CUS  REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_CUSTOMER
--
-- Parameters  :
--   :target_quarter  VARCHAR  e.g. '2026-Q1'
--
-- Quarter derivation from CLOSE_DATE:
--   TO_CHAR(DATE_TRUNC('QUARTER', CLOSE_DATE), 'YYYY') || '-Q' || QUARTER(CLOSE_DATE)
--
-- Note: ACCOUNT_ID in RAW_OPP is matched to MASTER_CUSTOMER_ID in EXEC_DECK_CUS.
--       If your org uses a SFDC-to-MCID bridging table, substitute it here.
-- =============================================================================

WITH

-- ---------------------------------------------------------------------------
-- 1. Closed-Lost opportunities in target quarter
--    Use MAX per ACCOUNT_ID + OPPORTUNITY_ID to avoid duplicates from RAW_OPP
-- ---------------------------------------------------------------------------
raw_opp_base AS (
    SELECT
        ACCOUNT_ID,
        OPPORTUNITY_ID,
        ACCOUNT_NAME                                                AS opp_account_name,
        STAGE_NAME,
        CLOSE_DATE,
        TYPE_OF_CHURN_C,
        CHURN_CATEGORY_C,
        AMOUNT                                                      AS opp_amount,
        -- Derive quarter label from close date
        TO_CHAR(DATE_TRUNC('YEAR', CLOSE_DATE), 'YYYY')
        || '-Q'
        || QUARTER(CLOSE_DATE)                                      AS opp_date_yq
    FROM REPORTING.SALESFORCE.RAW_OPPORTUNITY_REPORT
    WHERE STAGE_NAME = 'Closed Lost'
      AND (
          TO_CHAR(DATE_TRUNC('YEAR', CLOSE_DATE), 'YYYY')
          || '-Q'
          || QUARTER(CLOSE_DATE)
      ) = :target_quarter
),

-- Deduplicate: one row per ACCOUNT_ID + OPPORTUNITY_ID (take max amount)
raw_opp_dedup AS (
    SELECT
        ACCOUNT_ID,
        OPPORTUNITY_ID,
        opp_account_name,
        CLOSE_DATE,
        TYPE_OF_CHURN_C,
        CHURN_CATEGORY_C,
        MAX(opp_amount)                                             AS opp_amount,
        opp_date_yq
    FROM raw_opp_base
    GROUP BY
        ACCOUNT_ID,
        OPPORTUNITY_ID,
        opp_account_name,
        CLOSE_DATE,
        TYPE_OF_CHURN_C,
        CHURN_CATEGORY_C,
        opp_date_yq
),

-- For each account, keep the latest Closed-Lost opp (for churn reason)
opp_latest AS (
    SELECT
        ACCOUNT_ID,
        opp_account_name,
        CLOSE_DATE,
        TYPE_OF_CHURN_C,
        CHURN_CATEGORY_C,
        opp_amount
    FROM raw_opp_dedup
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY ACCOUNT_ID
        ORDER BY CLOSE_DATE DESC
    ) = 1
),

-- ---------------------------------------------------------------------------
-- 2. EXEC_DECK_CUS: churned accounts in target quarter (ARR_CHURN < 0)
-- ---------------------------------------------------------------------------
cus_churned AS (
    SELECT
        MASTER_CUSTOMER_ID,
        ACCOUNT_NAME,
        REGION,
        TERRITORY,
        ARR_RENEWAL,
        ARR_CHURN,
        DATE_YQ
    FROM REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_CUSTOMER
    WHERE DATE_YQ = :target_quarter
      AND ARR_CHURN < 0
),

-- ---------------------------------------------------------------------------
-- 3. Join: match ACCOUNT_ID (RAW_OPP) to MASTER_CUSTOMER_ID (CUS)
-- ---------------------------------------------------------------------------
joined AS (
    SELECT
        c.DATE_YQ,
        c.MASTER_CUSTOMER_ID,
        COALESCE(c.ACCOUNT_NAME, ol.opp_account_name)               AS account_name,
        c.REGION,
        c.TERRITORY,
        ROUND(c.ARR_RENEWAL, 2)                                     AS arr_renewal,
        ROUND(c.ARR_CHURN,   2)                                     AS arr_churn,
        ol.TYPE_OF_CHURN_C,
        ol.CHURN_CATEGORY_C,
        ol.CLOSE_DATE,
        ol.opp_amount
    FROM cus_churned c
    LEFT JOIN opp_latest ol ON ol.ACCOUNT_ID = c.MASTER_CUSTOMER_ID
)

-- =============================================================================
-- RESULT 1: SUMMARY — churn reasons rolled up
-- =============================================================================
SELECT
    'SUMMARY'                                                       AS result_type,
    COALESCE(TYPE_OF_CHURN_C,   'Not Captured')                     AS type_of_churn,
    COALESCE(CHURN_CATEGORY_C,  'Not Captured')                     AS churn_category,
    COUNT(DISTINCT MASTER_CUSTOMER_ID)                              AS account_count,
    ROUND(SUM(arr_churn), 2)                                        AS total_churn_arr,
    ROUND(AVG(arr_churn), 2)                                        AS avg_churn_arr_per_account,
    NULL                                                            AS account_name,
    NULL                                                            AS region,
    NULL                                                            AS territory,
    NULL::DATE                                                      AS close_date
FROM joined
GROUP BY
    TYPE_OF_CHURN_C,
    CHURN_CATEGORY_C

UNION ALL

-- =============================================================================
-- RESULT 2: DETAIL — account-level churn list
-- =============================================================================
SELECT
    'DETAIL'                                                        AS result_type,
    COALESCE(TYPE_OF_CHURN_C,  'Not Captured')                     AS type_of_churn,
    COALESCE(CHURN_CATEGORY_C, 'Not Captured')                     AS churn_category,
    NULL                                                            AS account_count,
    NULL                                                            AS total_churn_arr,
    NULL                                                            AS avg_churn_arr_per_account,
    account_name,
    REGION                                                          AS region,
    TERRITORY                                                       AS territory,
    CLOSE_DATE                                                      AS close_date
FROM joined

ORDER BY
    result_type DESC,                       -- SUMMARY rows first
    type_of_churn,
    churn_category,
    total_churn_arr ASC NULLS LAST,         -- for SUMMARY: most churned first
    account_name
;
