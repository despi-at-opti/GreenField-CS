-- =============================================================================
-- FILE 05: CROSS-SELL / UPSELL ANALYSIS — updated 2026-06
-- =============================================================================
-- Description : Two result sets comparing SST_REPORT snapshots at consecutive
--               quarter ends to identify product additions (cross-sell) and
--               ARR expansion on existing products (upsell).
--
-- Definitions :
--   Cross-sell  = existing customer adds a product group they did NOT hold at start
--                 ARR = the new product line's ARR at end snapshot
--   Upsell      = existing customer increases ARR on a product group they ALREADY held
--                 ARR = end ARR minus start ARR for that product group
--
-- Parameters  : :start_quarter  VARCHAR  e.g. '2026-Q1'
--               :end_quarter    VARCHAR  e.g. '2026-Q2'
--
-- Tables      : REPORTING.ARR_SST.SST_REPORT
--               Always filter: DAY(SNAPSHOT_DATE) >= 28
--               Always filter: NEW_PRODUCT_SOLUTION != 'EOL'
--               Key columns  : MCID (not MASTER_CUSTOMER_ID), ARR (not CONTRACTED_ARR)
--
-- Section tags: "cross_sell"  → product_group, account_count, total_arr
--               "upsell"      → product_group, account_count, total_arr_increase
--
-- Notes:
--   • UNION ALL is blocked by the MCP configuration — run each query separately
--     and merge in Python before saving to JSON.
--   • "Existing customers" = accounts present in BOTH start and end snapshots.
--   • Cross-sell rows with total_arr = 0 are bundled/licensed products —
--     include in the table but exclude from the ARR bar chart.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- QUERY 1: CROSS-SELL — existing customers adding a net-new product
-- ---------------------------------------------------------------------------
-- Grain    : product_group
-- Metric   : account_count (# distinct MCIDs adding this product),
--            total_arr     (sum of that product's ARR at end snapshot)
-- Section  : "cross_sell"
-- ---------------------------------------------------------------------------

WITH
snap_start AS (
    SELECT MCID, UPDATED_PRODUCT_GROUP, ARR
    FROM REPORTING.ARR_SST.SST_REPORT
    WHERE DAY(SNAPSHOT_DATE) >= 28
      AND NEW_PRODUCT_SOLUTION != 'EOL'
      AND TO_CHAR(SNAPSHOT_DATE, 'YYYY') || '-Q' || QUARTER(SNAPSHOT_DATE) = :start_quarter
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY MCID, UPDATED_PRODUCT_GROUP
        ORDER BY SNAPSHOT_DATE DESC
    ) = 1
),

snap_end AS (
    SELECT MCID, UPDATED_PRODUCT_GROUP, ARR
    FROM REPORTING.ARR_SST.SST_REPORT
    WHERE DAY(SNAPSHOT_DATE) >= 28
      AND NEW_PRODUCT_SOLUTION != 'EOL'
      AND TO_CHAR(SNAPSHOT_DATE, 'YYYY') || '-Q' || QUARTER(SNAPSHOT_DATE) = :end_quarter
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY MCID, UPDATED_PRODUCT_GROUP
        ORDER BY SNAPSHOT_DATE DESC
    ) = 1
),

-- Only accounts present at BOTH snapshots (existing customers)
existing_accounts AS (
    SELECT DISTINCT s.MCID
    FROM snap_start s
    INNER JOIN snap_end e ON s.MCID = e.MCID
),

-- Cross-sell: product exists at end but NOT at start, for existing accounts
cross_sell AS (
    SELECT e.MCID, e.UPDATED_PRODUCT_GROUP, e.ARR
    FROM snap_end e
    INNER JOIN existing_accounts ea ON e.MCID = ea.MCID
    LEFT JOIN snap_start s
        ON s.MCID = e.MCID
       AND s.UPDATED_PRODUCT_GROUP = e.UPDATED_PRODUCT_GROUP
    WHERE s.MCID IS NULL   -- product was NOT present at start
)

SELECT
    UPDATED_PRODUCT_GROUP       AS product_group,
    COUNT(DISTINCT MCID)        AS account_count,
    ROUND(SUM(ARR), 0)          AS total_arr
FROM cross_sell
GROUP BY UPDATED_PRODUCT_GROUP
ORDER BY total_arr DESC;


-- ---------------------------------------------------------------------------
-- QUERY 2: UPSELL — existing customers growing ARR on products they already hold
-- ---------------------------------------------------------------------------
-- Grain    : product_group
-- Metric   : account_count      (# distinct MCIDs with ARR growth on this product),
--            total_arr_increase (sum of end ARR minus start ARR for those accounts)
-- Section  : "upsell"
-- ---------------------------------------------------------------------------

WITH
snap_start AS (
    SELECT MCID, UPDATED_PRODUCT_GROUP, ARR
    FROM REPORTING.ARR_SST.SST_REPORT
    WHERE DAY(SNAPSHOT_DATE) >= 28
      AND NEW_PRODUCT_SOLUTION != 'EOL'
      AND TO_CHAR(SNAPSHOT_DATE, 'YYYY') || '-Q' || QUARTER(SNAPSHOT_DATE) = :start_quarter
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY MCID, UPDATED_PRODUCT_GROUP
        ORDER BY SNAPSHOT_DATE DESC
    ) = 1
),

snap_end AS (
    SELECT MCID, UPDATED_PRODUCT_GROUP, ARR
    FROM REPORTING.ARR_SST.SST_REPORT
    WHERE DAY(SNAPSHOT_DATE) >= 28
      AND NEW_PRODUCT_SOLUTION != 'EOL'
      AND TO_CHAR(SNAPSHOT_DATE, 'YYYY') || '-Q' || QUARTER(SNAPSHOT_DATE) = :end_quarter
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY MCID, UPDATED_PRODUCT_GROUP
        ORDER BY SNAPSHOT_DATE DESC
    ) = 1
),

-- Upsell: same product group, ARR strictly higher at end than at start
upsell AS (
    SELECT
        e.MCID,
        e.UPDATED_PRODUCT_GROUP,
        (e.ARR - s.ARR)         AS arr_increase
    FROM snap_end e
    INNER JOIN snap_start s
        ON e.MCID = s.MCID
       AND e.UPDATED_PRODUCT_GROUP = s.UPDATED_PRODUCT_GROUP
    WHERE e.ARR > s.ARR
)

SELECT
    UPDATED_PRODUCT_GROUP           AS product_group,
    COUNT(DISTINCT MCID)            AS account_count,
    ROUND(SUM(arr_increase), 0)     AS total_arr_increase
FROM upsell
GROUP BY UPDATED_PRODUCT_GROUP
ORDER BY total_arr_increase DESC;
