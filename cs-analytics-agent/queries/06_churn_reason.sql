-- =============================================================================
-- 06_churn_reason.sql
-- Churn Code & Category Breakdown by Quarter
-- =============================================================================
-- Description : Quarterly breakdown of churn codes (TYPE_OF_CHURN_C) and churn
--               categories (CHURN_CATEGORY_C) from Salesforce Lost opportunities,
--               keyed on RENEWAL_CONTRACT_START_DATE_C.
--
--               *** USAGE NOTE ***
--               These churn reason fields are SOFT CONTEXT ONLY — use them to
--               provide narrative colour and directional commentary alongside
--               other analyses. Do NOT generate charts or graphs from this data;
--               render as a plain reference table with qualitative commentary.
--
-- Sources:
--   RAW_OPP  REPORTING.SALESFORCE.RAW_OPPORTUNITY_REPORT
--
-- Parameters  :
--   :target_year  INTEGER  e.g. 2026
--
-- Time dimension: RENEWAL_CONTRACT_START_DATE_C, H1 only (months 1–6).
--   Remove the MONTH(...) < 7 filter to extend to full year.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- QUERY 1: Churn code (TYPE_OF_CHURN_C) breakdown by quarter
-- Informational context only — do not chart.
-- ---------------------------------------------------------------------------
SELECT
    COALESCE(TYPE_OF_CHURN_C, 'Not Captured')                       AS type_of_churn,
    YEAR(RENEWAL_CONTRACT_START_DATE_C)
        || '_Q'
        || QUARTER(RENEWAL_CONTRACT_START_DATE_C)                   AS yyyy_qq,
    COUNT(DISTINCT ACCOUNT_ID)                                      AS account_count
FROM REPORTING.SALESFORCE.RAW_OPPORTUNITY_REPORT
WHERE
    STAGE_NAME ILIKE '%Lost%'
    AND YEAR(RENEWAL_CONTRACT_START_DATE_C)  = :target_year
    AND MONTH(RENEWAL_CONTRACT_START_DATE_C) < 7          -- H1; remove for full year
GROUP BY 1, 2
ORDER BY 1, 2
;

-- ---------------------------------------------------------------------------
-- QUERY 2: Churn category (CHURN_CATEGORY_C) breakdown by quarter
-- Informational context only — do not chart.
-- ---------------------------------------------------------------------------
SELECT
    COALESCE(CHURN_CATEGORY_C, 'Not Captured')                      AS churn_category,
    YEAR(RENEWAL_CONTRACT_START_DATE_C)
        || '_Q'
        || QUARTER(RENEWAL_CONTRACT_START_DATE_C)                   AS yyyy_qq,
    COUNT(DISTINCT ACCOUNT_ID)                                      AS account_count
FROM REPORTING.SALESFORCE.RAW_OPPORTUNITY_REPORT
WHERE
    STAGE_NAME ILIKE '%Lost%'
    AND YEAR(RENEWAL_CONTRACT_START_DATE_C)  = :target_year
    AND MONTH(RENEWAL_CONTRACT_START_DATE_C) < 7          -- H1; remove for full year
GROUP BY 1, 2
ORDER BY 1, 2
;
