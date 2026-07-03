-- =============================================================================
-- 01_regional_trend.sql
-- NA & EMEA Renewal Rate Trend (multi-quarter)
-- =============================================================================
-- Description : Historical renewal ARR, churn ARR, and renewal rate for
--               NA and EMEA regions across the last N quarters.
--               Used by 01_global_snapshot.py to render dual trend lines.
--
-- Sources:
--   EXEC_DECK_CUS  REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_CUSTOMER
--
-- Parameters  :
--   :quarters  comma-separated list  e.g. '2025-Q3','2025-Q4','2026-Q1','2026-Q2'
--
-- Output saved to: data/01_regional_trend.json
--   columns: quarter, region, renewal_count, renewal_arr, churn_arr, renewal_rate
-- =============================================================================

SELECT
    DATE_YQ                                                             AS quarter,
    REGION                                                              AS region,
    COUNT(DISTINCT MASTER_CUSTOMER_ID)                                  AS renewal_count,
    ROUND(SUM(ARR_RENEWAL), 2)                                          AS renewal_arr,
    ROUND(SUM(ARR_CHURN), 2)                                            AS churn_arr,
    ROUND(
        SUM(ARR_RENEWAL + ARR_CHURN) / NULLIF(SUM(ARR_RENEWAL), 0),
    4)                                                                  AS renewal_rate
FROM REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_CUSTOMER
WHERE DATE_YQ IN ('2025-Q3','2025-Q4','2026-Q1','2026-Q2')
  AND REGION IN ('NA', 'EMEA')
GROUP BY DATE_YQ, REGION
ORDER BY DATE_YQ, REGION
;
