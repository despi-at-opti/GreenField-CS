-- =============================================================================
-- 03_detailed_renewals.sql
-- Account-Level Renewal Detail
-- =============================================================================
-- Description : One row per account for :target_quarter with renewal and churn
--               ARR, segment, ARR band, solution type, product groups, and a
--               retained/churned flag.
--
-- Sources:
--   EXEC_DECK_CUS  REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_CUSTOMER
--                  Grain: MASTER_CUSTOMER_ID × DATE_YQ  (primary)
--   EXEC_DECK_PG   REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP
--                  Deduplicated; used to aggregate product groups per account.
--   SST_REPORT     REPORTING.ARR_SST.SST_REPORT
--                  Used to derive Single/Multi solution type.
--                  Filters: DAY(SNAPSHOT_DATE) >= 28, NEW_PRODUCT_SOLUTION != 'EOL'
--   RENEWAL_OPP    REPORTING.GTM_ANALYTICS.RENEWAL_OPPORTUNITY
--                  Used via MAX(RENEWAL_FINAL_AMOUNT_USD) to get churn reasons.
--                  (Joined in FILE 4; included here for completeness.)
--
-- Parameters  :
--   :target_quarter  VARCHAR  e.g. '2026-Q1'
--
-- Revenue Segment : Enterprise >= 250k | Mid-Market >= 100k | else Digital
-- ARR Bands       : <=100k | 100k-250k | 250k-500k | 500k+
-- =============================================================================

WITH

-- ---------------------------------------------------------------------------
-- 1. Customer base: EXEC_DECK_CUS filtered to target quarter
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
),

-- ---------------------------------------------------------------------------
-- 2. Product groups per account from EXEC_DECK_PG (deduped, target quarter)
--    Concatenate distinct non-EOL product groups as a comma-separated string.
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
            WITHIN GROUP (ORDER BY PRODUCT_GROUP_CLEANED)       AS product_groups
    FROM pg_dedup
    GROUP BY MASTER_CUSTOMER_ID
),

-- ---------------------------------------------------------------------------
-- 3. Solution type from SST_REPORT
--    Take the latest snapshot (DAY >= 28) in the last month of :target_quarter.
--    Derive Q end month:  Q1→03, Q2→06, Q3→09, Q4→12
--    Count distinct non-EOL product solutions per MCID.
-- ---------------------------------------------------------------------------
sst_snap AS (
    SELECT
        MCID                                                        AS MASTER_CUSTOMER_ID,
        UPDATED_PRODUCT_GROUP,
        SNAPSHOT_DATE,
        -- Identify the most recent snapshot month within target quarter
        MAX(SNAPSHOT_DATE) OVER (PARTITION BY MCID)                 AS latest_snap
    FROM REPORTING.ARR_SST.SST_REPORT
    WHERE DAY(SNAPSHOT_DATE) >= 28
      AND NEW_PRODUCT_SOLUTION != 'EOL'
      -- Filter to the quarter: compare year+quarter extracted from SNAPSHOT_DATE
      AND (
          TO_CHAR(DATE_TRUNC('YEAR', SNAPSHOT_DATE), 'YYYY')
          || '-Q'
          || QUARTER(SNAPSHOT_DATE)
      ) = :target_quarter
),

sst_latest AS (
    -- Keep only the latest snapshot date per customer
    SELECT DISTINCT MASTER_CUSTOMER_ID, UPDATED_PRODUCT_GROUP
    FROM sst_snap
    WHERE SNAPSHOT_DATE = latest_snap
),

sol_type AS (
    SELECT
        MASTER_CUSTOMER_ID,
        COUNT(DISTINCT UPDATED_PRODUCT_GROUP)                       AS solution_count,
        CASE
            WHEN COUNT(DISTINCT UPDATED_PRODUCT_GROUP) <= 1 THEN 'Single'
            ELSE 'Multi'
        END                                                         AS sol_type
    FROM sst_latest
    GROUP BY MASTER_CUSTOMER_ID
)

-- ---------------------------------------------------------------------------
-- Final SELECT: join everything together
-- ---------------------------------------------------------------------------
SELECT
    c.DATE_YQ,
    c.MASTER_CUSTOMER_ID,
    c.ACCOUNT_NAME,
    c.PRIMARY_CSM,
    c.REGION,
    c.TERRITORY,

    -- ARR figures
    ROUND(c.ARR_RENEWAL, 2)                                         AS ARR_RENEWAL,
    ROUND(c.ARR_CHURN,   2)                                         AS ARR_CHURN,

    -- Revenue segment (derived from account ARR_RENEWAL)
    CASE
        WHEN c.ARR_RENEWAL >= 250000 THEN 'Enterprise'
        WHEN c.ARR_RENEWAL >= 100000 THEN 'Mid-Market'
        ELSE 'Digital'
    END                                                             AS revenue_segment,

    -- ARR Band
    CASE
        WHEN c.ARR_RENEWAL <= 100000  THEN '<=100k'
        WHEN c.ARR_RENEWAL <= 250000  THEN '100k-250k'
        WHEN c.ARR_RENEWAL <= 500000  THEN '250k-500k'
        ELSE '500k+'
    END                                                             AS arr_band,

    -- Single / Multi solution type from SST
    COALESCE(st.sol_type, 'Unknown')                                AS sol_type,

    -- Comma-separated list of non-EOL product groups
    COALESCE(pg.product_groups, 'No Product Data')                  AS product_groups,

    -- Retained / Downsell / Churned flag
    CASE
        WHEN c.ARR_CHURN = 0                                        THEN 'Retained'
        WHEN c.ARR_CHURN < 0
             AND (c.ARR_RENEWAL + c.ARR_CHURN) > 0                  THEN 'Downsell'
        ELSE 'Churned'
    END                                                             AS retained_churned,

    -- Per-account renewal rate
    CASE
        WHEN c.ARR_RENEWAL = 0 OR c.ARR_RENEWAL IS NULL THEN NULL
        ELSE ROUND(
            (c.ARR_RENEWAL + c.ARR_CHURN) / NULLIF(c.ARR_RENEWAL, 0),
        4)
    END                                                             AS renewal_rate

FROM cus c
LEFT JOIN product_groups_agg pg ON pg.MASTER_CUSTOMER_ID = c.MASTER_CUSTOMER_ID
LEFT JOIN sol_type            st ON st.MASTER_CUSTOMER_ID = c.MASTER_CUSTOMER_ID

ORDER BY c.ARR_RENEWAL DESC NULLS LAST
;
