-- =============================================================================
-- 05_cross_upsell.sql
-- Cross-Sell / Upsell Analysis — Product Portfolio Movement
-- =============================================================================
-- Description : Compares SST_REPORT snapshots at two quarter-end dates to
--               identify product additions and losses per account.
--
-- Source      : REPORTING.ARR_SST.SST_REPORT
--               Always filter DAY(SNAPSHOT_DATE) >= 28
--               Always filter NEW_PRODUCT_SOLUTION != 'EOL'
--
-- Account names from : REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_CUSTOMER
--
-- Parameters  :
--   :start_quarter  VARCHAR  Start quarter in 'YYYY-QN' format, e.g. '2025-Q4'
--   :end_quarter    VARCHAR  End quarter in 'YYYY-QN' format,   e.g. '2026-Q1'
--
-- Output:
--   One row per MCID showing products added, products lost, ARR at each
--   snapshot, and summary statistics.
-- =============================================================================

WITH

-- ---------------------------------------------------------------------------
-- 1. snap_start: latest valid SST snapshot within :start_quarter
--    "Latest" = MAX(SNAPSHOT_DATE) where DAY >= 28 in the quarter's final month
-- ---------------------------------------------------------------------------
snap_start_raw AS (
    SELECT
        MASTER_CUSTOMER_ID,
        UPDATED_PRODUCT_GROUP,
        SNAPSHOT_DATE,
        ARR                                                         AS snapshot_arr
    FROM REPORTING.ARR_SST.SST_REPORT
    WHERE DAY(SNAPSHOT_DATE) >= 28
      AND NEW_PRODUCT_SOLUTION != 'EOL'
      AND (
          TO_CHAR(DATE_TRUNC('YEAR', SNAPSHOT_DATE), 'YYYY')
          || '-Q'
          || QUARTER(SNAPSHOT_DATE)
      ) = :start_quarter
),

-- Keep only the max snapshot date per customer in the start quarter
snap_start_max AS (
    SELECT MASTER_CUSTOMER_ID, MAX(SNAPSHOT_DATE) AS max_snap_date
    FROM snap_start_raw
    GROUP BY MASTER_CUSTOMER_ID
),

snap_start AS (
    SELECT r.MASTER_CUSTOMER_ID, r.UPDATED_PRODUCT_GROUP, r.SNAPSHOT_DATE,
           r.snapshot_arr
    FROM snap_start_raw r
    JOIN snap_start_max m
      ON r.MASTER_CUSTOMER_ID = m.MASTER_CUSTOMER_ID
     AND r.SNAPSHOT_DATE      = m.max_snap_date
),

-- ---------------------------------------------------------------------------
-- 2. snap_end: latest valid SST snapshot within :end_quarter
-- ---------------------------------------------------------------------------
snap_end_raw AS (
    SELECT
        MASTER_CUSTOMER_ID,
        UPDATED_PRODUCT_GROUP,
        SNAPSHOT_DATE,
        ARR                                                         AS snapshot_arr
    FROM REPORTING.ARR_SST.SST_REPORT
    WHERE DAY(SNAPSHOT_DATE) >= 28
      AND NEW_PRODUCT_SOLUTION != 'EOL'
      AND (
          TO_CHAR(DATE_TRUNC('YEAR', SNAPSHOT_DATE), 'YYYY')
          || '-Q'
          || QUARTER(SNAPSHOT_DATE)
      ) = :end_quarter
),

snap_end_max AS (
    SELECT MASTER_CUSTOMER_ID, MAX(SNAPSHOT_DATE) AS max_snap_date
    FROM snap_end_raw
    GROUP BY MASTER_CUSTOMER_ID
),

snap_end AS (
    SELECT r.MASTER_CUSTOMER_ID, r.UPDATED_PRODUCT_GROUP, r.SNAPSHOT_DATE,
           r.snapshot_arr
    FROM snap_end_raw r
    JOIN snap_end_max m
      ON r.MASTER_CUSTOMER_ID = m.MASTER_CUSTOMER_ID
     AND r.SNAPSHOT_DATE      = m.max_snap_date
),

-- ---------------------------------------------------------------------------
-- 3. products_start: set of products per MCID at start
-- ---------------------------------------------------------------------------
products_start AS (
    SELECT DISTINCT MASTER_CUSTOMER_ID, UPDATED_PRODUCT_GROUP AS product_group
    FROM snap_start
),

-- ---------------------------------------------------------------------------
-- 4. products_end: set of products per MCID at end
-- ---------------------------------------------------------------------------
products_end AS (
    SELECT DISTINCT MASTER_CUSTOMER_ID, UPDATED_PRODUCT_GROUP AS product_group
    FROM snap_end
),

-- ---------------------------------------------------------------------------
-- 5. new_products: products in end but NOT in start (cross-sell / upsell)
-- ---------------------------------------------------------------------------
new_products AS (
    SELECT
        e.MASTER_CUSTOMER_ID,
        e.product_group                                             AS product_added
    FROM products_end   e
    LEFT JOIN products_start s
      ON s.MASTER_CUSTOMER_ID = e.MASTER_CUSTOMER_ID
     AND s.product_group      = e.product_group
    WHERE s.product_group IS NULL
),

-- ---------------------------------------------------------------------------
-- 6. lost_products: products in start but NOT in end (churn / downsell)
-- ---------------------------------------------------------------------------
lost_products AS (
    SELECT
        s.MASTER_CUSTOMER_ID,
        s.product_group                                             AS product_lost
    FROM products_start s
    LEFT JOIN products_end e
      ON e.MASTER_CUSTOMER_ID = s.MASTER_CUSTOMER_ID
     AND e.product_group      = s.product_group
    WHERE e.product_group IS NULL
),

-- ---------------------------------------------------------------------------
-- 7. ARR summary per MCID at start and end
-- ---------------------------------------------------------------------------
arr_start AS (
    SELECT MASTER_CUSTOMER_ID, ROUND(SUM(snapshot_arr), 2)         AS start_arr
    FROM snap_start
    GROUP BY MASTER_CUSTOMER_ID
),

arr_end AS (
    SELECT MASTER_CUSTOMER_ID, ROUND(SUM(snapshot_arr), 2)         AS end_arr
    FROM snap_end
    GROUP BY MASTER_CUSTOMER_ID
),

-- ---------------------------------------------------------------------------
-- 8. Aggregate new and lost product lists per MCID
-- ---------------------------------------------------------------------------
new_products_agg AS (
    SELECT
        MASTER_CUSTOMER_ID,
        LISTAGG(product_added, ', ')
            WITHIN GROUP (ORDER BY product_added)                   AS products_added
    FROM new_products
    GROUP BY MASTER_CUSTOMER_ID
),

lost_products_agg AS (
    SELECT
        MASTER_CUSTOMER_ID,
        LISTAGG(product_lost, ', ')
            WITHIN GROUP (ORDER BY product_lost)                    AS products_lost
    FROM lost_products
    GROUP BY MASTER_CUSTOMER_ID
),

-- ---------------------------------------------------------------------------
-- 9. Account names from EXEC_DECK_CUS (latest available quarter)
-- ---------------------------------------------------------------------------
account_names AS (
    SELECT DISTINCT MASTER_CUSTOMER_ID, ACCOUNT_NAME
    FROM REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_CUSTOMER
    WHERE DATE_YQ IN (:start_quarter, :end_quarter)
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY MASTER_CUSTOMER_ID
        ORDER BY DATE_YQ DESC
    ) = 1
),

-- ---------------------------------------------------------------------------
-- 10. Full account universe: all MCIDs present in either snapshot
-- ---------------------------------------------------------------------------
all_accounts AS (
    SELECT MASTER_CUSTOMER_ID FROM snap_start
    UNION
    SELECT MASTER_CUSTOMER_ID FROM snap_end
)

-- ---------------------------------------------------------------------------
-- Final output
-- ---------------------------------------------------------------------------
SELECT
    a.MASTER_CUSTOMER_ID,
    an.ACCOUNT_NAME,

    -- Products added (cross-sell / upsell)
    COALESCE(np.products_added, '')                                 AS products_added,
    -- Products lost (downsell / churn)
    COALESCE(lp.products_lost,  '')                                 AS products_lost,

    -- ARR at each snapshot
    COALESCE(s_arr.start_arr, 0)                                    AS start_arr,
    COALESCE(e_arr.end_arr,   0)                                    AS end_arr,
    COALESCE(e_arr.end_arr, 0) - COALESCE(s_arr.start_arr, 0)      AS arr_change,

    -- Movement classification
    CASE
        WHEN np.products_added IS NOT NULL
         AND lp.products_lost  IS NOT NULL THEN 'Swap'
        WHEN np.products_added IS NOT NULL THEN 'Cross-Sell / Upsell'
        WHEN lp.products_lost  IS NOT NULL THEN 'Downsell / Product Loss'
        ELSE 'No Change'
    END                                                             AS movement_type,

    -- Was this account present at start and/or end?
    CASE WHEN s_arr.MASTER_CUSTOMER_ID IS NOT NULL THEN 'Yes' ELSE 'No' END AS present_at_start,
    CASE WHEN e_arr.MASTER_CUSTOMER_ID IS NOT NULL THEN 'Yes' ELSE 'No' END AS present_at_end

FROM all_accounts        a
LEFT JOIN account_names  an    ON an.MASTER_CUSTOMER_ID  = a.MASTER_CUSTOMER_ID
LEFT JOIN new_products_agg np  ON np.MASTER_CUSTOMER_ID  = a.MASTER_CUSTOMER_ID
LEFT JOIN lost_products_agg lp ON lp.MASTER_CUSTOMER_ID  = a.MASTER_CUSTOMER_ID
LEFT JOIN arr_start        s_arr ON s_arr.MASTER_CUSTOMER_ID = a.MASTER_CUSTOMER_ID
LEFT JOIN arr_end          e_arr ON e_arr.MASTER_CUSTOMER_ID = a.MASTER_CUSTOMER_ID

-- Only include accounts with an actual product movement or ARR change
WHERE np.products_added IS NOT NULL
   OR lp.products_lost  IS NOT NULL

ORDER BY ABS(arr_change) DESC NULLS LAST
;

-- =============================================================================
-- Summary view: most frequently added / lost products across all accounts
-- =============================================================================
-- Run this supplementary query separately to get aggregate product frequencies.
/*
WITH new_products_detail AS (
    SELECT
        e.UPDATED_PRODUCT_GROUP                                     AS product_group,
        COUNT(DISTINCT e.MASTER_CUSTOMER_ID)                        AS customers_added
    FROM REPORTING.ARR_SST.SST_REPORT e
    WHERE DAY(e.SNAPSHOT_DATE) >= 28
      AND e.NEW_PRODUCT_SOLUTION != 'EOL'
      AND (
          TO_CHAR(DATE_TRUNC('YEAR', e.SNAPSHOT_DATE), 'YYYY')
          || '-Q' || QUARTER(e.SNAPSHOT_DATE)
      ) = :end_quarter
      AND NOT EXISTS (
          SELECT 1 FROM REPORTING.ARR_SST.SST_REPORT s
          WHERE s.MASTER_CUSTOMER_ID = e.MASTER_CUSTOMER_ID
            AND s.UPDATED_PRODUCT_GROUP = e.UPDATED_PRODUCT_GROUP
            AND DAY(s.SNAPSHOT_DATE) >= 28
            AND s.NEW_PRODUCT_SOLUTION != 'EOL'
            AND (
                TO_CHAR(DATE_TRUNC('YEAR', s.SNAPSHOT_DATE), 'YYYY')
                || '-Q' || QUARTER(s.SNAPSHOT_DATE)
            ) = :start_quarter
      )
    GROUP BY e.UPDATED_PRODUCT_GROUP
)
SELECT * FROM new_products_detail ORDER BY customers_added DESC;
*/
