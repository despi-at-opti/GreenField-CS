-- =============================================================================
-- 04_churn_list.sql
-- Churned Accounts Detail
-- =============================================================================
-- Description : Filtered view of churned accounts for :target_quarter.
--               Extends the 03_detailed_renewals logic with:
--               - Churn reason from RAW_OPPORTUNITY_REPORT
--               - Avg experiments per month (Web Experimentation customers only)
--
-- Sources:
--   EXEC_DECK_CUS  REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_CUSTOMER
--   EXEC_DECK_PG   REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP
--   SST_REPORT     REPORTING.ARR_SST.SST_REPORT
--   RAW_OPP        REPORTING.SALESFORCE.RAW_OPPORTUNITY_REPORT
--   EXPERIMENT_METRICS  REPORTING.OPTI_APPLICATION.EXPERIMENT_METRICS
--   OA_CUSTOMER_DETAIL  REPORTING.OPTI_APPLICATION.OA_CUSTOMER_DETAIL
--
-- Parameters  :
--   :target_quarter  VARCHAR  e.g. '2026-Q1'
--
-- Note: churn reason is sourced from the most recent Closed-Lost opportunity
--       per account within the target quarter, using TYPE_OF_CHURN_C and
--       CHURN_CATEGORY_C fields.
-- =============================================================================

WITH

-- ---------------------------------------------------------------------------
-- 1. Customer base: EXEC_DECK_CUS — churned accounts only
-- ---------------------------------------------------------------------------
cus AS (
    SELECT
        DATE_YQ,
        MASTER_CUSTOMER_ID,
        ACCOUNT_NAME,
        PRIMARY_CSM,
        REGION,
        TERRITORY,
        ARR_RENEWAL,
        ARR_CHURN
    FROM REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_CUSTOMER
    WHERE DATE_YQ = :target_quarter
      AND ARR_CHURN < 0
),

-- ---------------------------------------------------------------------------
-- 2. Product groups per account (EXEC_DECK_PG, deduped, non-EOL)
-- ---------------------------------------------------------------------------
pg_dedup AS (
    SELECT *
    FROM REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP
    WHERE DATE_YQ = :target_quarter
      AND PRODUCT_GROUP_CLEANED NOT LIKE 'EOL%'
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY MASTER_CUSTOMER_ID, PRODUCT_GROUP_CLEANED, DATE_YM
        ORDER BY DATE_YM DESC
    ) = 1
),

product_groups_agg AS (
    SELECT
        MASTER_CUSTOMER_ID,
        LISTAGG(DISTINCT PRODUCT_GROUP_CLEANED, ', ')
            WITHIN GROUP (ORDER BY PRODUCT_GROUP_CLEANED)           AS product_groups,
        -- Flag: is this customer a Web Experimentation customer?
        MAX(CASE WHEN PRODUCT_GROUP_CLEANED = 'Web Experimentation'
                 THEN 1 ELSE 0 END)                                 AS is_web_exp
    FROM pg_dedup
    GROUP BY MASTER_CUSTOMER_ID
),

-- ---------------------------------------------------------------------------
-- 3. Solution type from SST_REPORT (same logic as FILE 3)
-- ---------------------------------------------------------------------------
sst_snap AS (
    SELECT
        MCID                                                        AS MASTER_CUSTOMER_ID,
        UPDATED_PRODUCT_GROUP,
        SNAPSHOT_DATE,
        MAX(SNAPSHOT_DATE) OVER (PARTITION BY MCID)                 AS latest_snap
    FROM REPORTING.ARR_SST.SST_REPORT
    WHERE DAY(SNAPSHOT_DATE) >= 28
      AND NEW_PRODUCT_SOLUTION != 'EOL'
      AND (
          TO_CHAR(DATE_TRUNC('YEAR', SNAPSHOT_DATE), 'YYYY')
          || '-Q'
          || QUARTER(SNAPSHOT_DATE)
      ) = :target_quarter
),

sst_latest AS (
    SELECT DISTINCT MASTER_CUSTOMER_ID, UPDATED_PRODUCT_GROUP
    FROM sst_snap
    WHERE SNAPSHOT_DATE = latest_snap
),

sol_type AS (
    SELECT
        MASTER_CUSTOMER_ID,
        CASE
            WHEN COUNT(DISTINCT UPDATED_PRODUCT_GROUP) <= 1 THEN 'Single'
            ELSE 'Multi'
        END                                                         AS sol_type
    FROM sst_latest
    GROUP BY MASTER_CUSTOMER_ID
),

-- ---------------------------------------------------------------------------
-- 4. Churn reason from RAW_OPPORTUNITY_REPORT
--    Take the most recent Closed-Lost opportunity per account in the quarter.
--    Match ACCOUNT_ID to MASTER_CUSTOMER_ID (best-effort; SFDC IDs may differ
--    from MCID — adjust the join key if your org uses a bridging table).
-- ---------------------------------------------------------------------------
raw_opp_quarter AS (
    SELECT
        ACCOUNT_ID,
        TYPE_OF_CHURN_C,
        CHURN_CATEGORY_C,
        CLOSE_DATE,
        ROW_NUMBER() OVER (
            PARTITION BY ACCOUNT_ID
            ORDER BY CLOSE_DATE DESC
        )                                                           AS rn
    FROM REPORTING.SALESFORCE.RAW_OPPORTUNITY_REPORT
    WHERE STAGE_NAME = 'Closed Lost'
      AND (
          TO_CHAR(DATE_TRUNC('YEAR', CLOSE_DATE), 'YYYY')
          || '-Q'
          || QUARTER(CLOSE_DATE)
      ) = :target_quarter
),

churn_reason AS (
    SELECT
        ACCOUNT_ID,
        TYPE_OF_CHURN_C,
        CHURN_CATEGORY_C,
        CLOSE_DATE
    FROM raw_opp_quarter
    WHERE rn = 1
),

-- ---------------------------------------------------------------------------
-- 5. Average experiments per month — Web Experimentation customers only
--    Join OA_CUSTOMER_DETAIL (maps SFDC account → app customer ID) to
--    EXPERIMENT_METRICS (experiment activity per customer per month).
--    Compute average monthly experiments over the trailing 12 months as a
--    health proxy, scoped to the quarter's year.
-- ---------------------------------------------------------------------------
ocd AS (
    SELECT
        ACCOUNT_ID,         -- SFDC Account ID
        CUSTOMER_ID         -- Opti Application customer ID
    FROM REPORTING.OPTI_APPLICATION.OA_CUSTOMER_DETAIL
),

exp_metrics AS (
    SELECT
        em.CUSTOMER_ID,
        AVG(em.EXPERIMENT_COUNT)                                    AS avg_experiments_per_month
    FROM REPORTING.OPTI_APPLICATION.EXPERIMENT_METRICS em
    -- Limit to the 12 months up to end of target quarter
    WHERE em.METRIC_MONTH >= DATEADD(
              'MONTH', -12,
              DATE_FROM_PARTS(
                  CAST(LEFT(:target_quarter, 4) AS INT),
                  CASE RIGHT(:target_quarter, 1)
                      WHEN '1' THEN 3
                      WHEN '2' THEN 6
                      WHEN '3' THEN 9
                      ELSE 12
                  END,
                  1
              )
          )
    GROUP BY em.CUSTOMER_ID
)

-- ---------------------------------------------------------------------------
-- Final SELECT
-- ---------------------------------------------------------------------------
SELECT
    c.DATE_YQ,
    c.MASTER_CUSTOMER_ID,
    c.ACCOUNT_NAME,
    c.PRIMARY_CSM,
    c.REGION,
    c.TERRITORY,

    ROUND(c.ARR_RENEWAL, 2)                                         AS ARR_RENEWAL,
    ROUND(c.ARR_CHURN,   2)                                         AS ARR_CHURN,

    -- Revenue segment
    CASE
        WHEN c.ARR_RENEWAL >= 250000 THEN 'Enterprise'
        WHEN c.ARR_RENEWAL >= 100000 THEN 'Mid-Market'
        ELSE 'Digital'
    END                                                             AS revenue_segment,

    -- ARR band
    CASE
        WHEN c.ARR_RENEWAL <= 100000  THEN '<=100k'
        WHEN c.ARR_RENEWAL <= 250000  THEN '100k-250k'
        WHEN c.ARR_RENEWAL <= 500000  THEN '250k-500k'
        ELSE '500k+'
    END                                                             AS arr_band,

    COALESCE(st.sol_type, 'Unknown')                                AS sol_type,
    COALESCE(pg.product_groups, 'No Product Data')                  AS product_groups,

    -- Per-account renewal rate (will be < 1 for churned accounts)
    ROUND(
        (c.ARR_RENEWAL + c.ARR_CHURN) / NULLIF(c.ARR_RENEWAL, 0),
    4)                                                              AS renewal_rate,

    -- Churn reason fields
    cr.TYPE_OF_CHURN_C                                              AS type_of_churn,
    cr.CHURN_CATEGORY_C                                             AS churn_category,
    cr.CLOSE_DATE                                                   AS churn_close_date,

    -- Experiment activity (Web Exp customers only; NULL for others)
    CASE
        WHEN pg.is_web_exp = 1
        THEN ROUND(em.avg_experiments_per_month, 1)
        ELSE NULL
    END                                                             AS avg_experiments_per_month

FROM cus c
LEFT JOIN product_groups_agg pg  ON pg.MASTER_CUSTOMER_ID = c.MASTER_CUSTOMER_ID
LEFT JOIN sol_type            st  ON st.MASTER_CUSTOMER_ID = c.MASTER_CUSTOMER_ID
LEFT JOIN churn_reason        cr  ON cr.ACCOUNT_ID          = c.MASTER_CUSTOMER_ID
LEFT JOIN ocd                     ON ocd.ACCOUNT_ID         = c.MASTER_CUSTOMER_ID
LEFT JOIN exp_metrics         em  ON em.CUSTOMER_ID         = ocd.CUSTOMER_ID

ORDER BY c.ARR_CHURN ASC  -- most churned ARR first (most negative)
;
