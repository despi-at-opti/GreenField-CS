-- =============================================================================
-- CHURN METHODOLOGY COMPARISON
-- EXEC_DECK_CUS method  vs  Power BI DAX-translated method
-- =============================================================================
-- Parameter: :target_quarter  VARCHAR  e.g. '2026-Q2'
--
-- EXEC_DECK method   : SUM(ARR_CHURN) from EXEC_DECK_RENEWAL_RATES_CUSTOMER
--                      Grain: MASTER_CUSTOMER_ID, pre-processed reporting layer
--
-- PBI method         : Line-item spread via AP_SPREAD_PCT
--                      Sources: RAW_OPPORTUNITY_LINE_ITEM_REPORT
--                               × RAW_OPPORTUNITY_REPORT
--                      TOTAL_CHURN = DOWNGRADE_AMOUNT_SPREAD + RENEWAL_AMOUNT_SPREAD
--                        DOWNGRADE : type='Renewal - Downgrade' AND stage IN
--                                    ('Closed Won','Closed Won - Finance')
--                                    → (renewal_baseline - renewal_final) / currency_rate
--                        CLOSED LOST: stage='Closed Lost'
--                                    → renewal_final / currency_rate
--                        AP_SPREAD_PCT = annual_price_c / SUM(annual_price_c) per opp
--
-- Quarter filter note: PBI uses YYYY_QN format (underscore); :target_quarter
--                      uses YYYY-QN (dash). The REPLACE() call below handles this.
--
-- Sign convention    : EXEC_DECK ARR_CHURN is negative (e.g. -500000).
--                      PBI total_churn is positive (magnitude). Both are shown
--                      as negative in output so they are directly comparable.
--
-- Run order          : Execute QUERY 1 first (global summary), then QUERY 2
--                      (account-level detail). Split into separate MCP calls.
-- =============================================================================


-- ===========================================================================
-- QUERY 1: GLOBAL SUMMARY — total churn by method, with delta
-- ===========================================================================

WITH

-- ---------------------------------------------------------------------------
-- A. EXEC_DECK churn — existing reporting layer
-- ---------------------------------------------------------------------------
exec_deck_churn AS (
    SELECT
        MASTER_CUSTOMER_ID,
        ACCOUNT_NAME,
        REGION,
        TERRITORY,
        ARR_RENEWAL,
        ARR_CHURN AS exec_deck_churn_arr          -- always negative
    FROM REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_CUSTOMER
    WHERE DATE_YQ = :target_quarter
      AND ARR_CHURN < 0
),

-- ---------------------------------------------------------------------------
-- B. PBI method — raw Salesforce line items spread to product level
--    Quarter filter: convert '2026-Q2' → '2026_Q2' to match PBI renewal_yq
-- ---------------------------------------------------------------------------
pbi_base AS (
    SELECT
        l.opportunity_id,
        o.id                                      AS opp_id,
        o.account_id,
        o.currency_rate_c,
        o.type,
        o.stage_name,
        o.renewal_baseline_c,
        o.renewal_final_amount_c,
        o.churn_type_c,
        o.churn_category_c,
        o.product_solution_c,
        o.product_group_c,
        o.renewal_contract_start_date_c,
        l.annual_price_c,
        YEAR(o.renewal_contract_start_date_c)::VARCHAR
            || '_Q'
            || QUARTER(o.renewal_contract_start_date_c)::VARCHAR      AS renewal_yq
    FROM REPORTING.SALESFORCE.RAW_OPPORTUNITY_LINE_ITEM_REPORT l
    JOIN REPORTING.SALESFORCE.RAW_OPPORTUNITY_REPORT o
        ON o.id = l.opportunity_id
    WHERE l.is_deleted IS DISTINCT FROM TRUE
      AND COALESCE(o.exclude_from_cs_pipeline_c, 'No') <> 'Yes'
      AND o.renewal_contract_start_date_c IS NOT NULL
      AND YEAR(o.renewal_contract_start_date_c)::VARCHAR
            || '_Q'
            || QUARTER(o.renewal_contract_start_date_c)::VARCHAR
          = REPLACE(:target_quarter, '-', '_')    -- '2026-Q2' → '2026_Q2'
),

-- Per-line measure: AP spread % + downgrade/closed-lost amounts
pbi_line_calc AS (
    SELECT
        b.*,
        -- AP_SPREAD_PCT: this line's share of the opp's total Annual Price
        DIV0(
            b.annual_price_c,
            SUM(b.annual_price_c) OVER (PARTITION BY b.opportunity_id)
        )                                                              AS ap_spread_pct,

        -- Downgrade amount (positive magnitude): Renewal-Downgrade opps only
        CASE
            WHEN b.type = 'Renewal - Downgrade'
             AND b.stage_name IN ('Closed Won', 'Closed Won - Finance')
            THEN DIV0(b.renewal_baseline_c,      b.currency_rate_c)
               - DIV0(b.renewal_final_amount_c,  b.currency_rate_c)
            ELSE 0
        END                                                            AS downgrade_amount,

        -- Closed-Lost renewal final amount (positive magnitude)
        CASE
            WHEN b.stage_name = 'Closed Lost'
            THEN DIV0(b.renewal_final_amount_c, b.currency_rate_c)
            ELSE 0
        END                                                            AS renewal_final_amount_cl
    FROM pbi_base b
),

-- Spread both amounts to line level; sum = total_churn per line
pbi_line_churn AS (
    SELECT
        c.account_id,
        c.opportunity_id,
        c.churn_type_c,
        c.churn_category_c,
        c.product_solution_c,
        c.product_group_c,
        (c.ap_spread_pct * c.downgrade_amount)
            + (c.ap_spread_pct * c.renewal_final_amount_cl)           AS total_churn   -- positive
    FROM pbi_line_calc c
),

-- Aggregate PBI churn to account level (negate to match EXEC_DECK sign)
pbi_churn_by_account AS (
    SELECT
        account_id,
        SUM(total_churn) * -1                                         AS pbi_churn_arr  -- make negative
    FROM pbi_line_churn
    WHERE total_churn != 0
    GROUP BY account_id
)

-- ---------------------------------------------------------------------------
-- RESULT 1: Global summary — one row per method
-- ---------------------------------------------------------------------------
SELECT
    'EXEC_DECK'                                                        AS method,
    COUNT(DISTINCT MASTER_CUSTOMER_ID)                                 AS churn_account_count,
    ROUND(SUM(exec_deck_churn_arr), 0)                                 AS total_churn_arr
FROM exec_deck_churn

UNION ALL

SELECT
    'PBI'                                                              AS method,
    COUNT(DISTINCT account_id)                                         AS churn_account_count,
    ROUND(SUM(pbi_churn_arr), 0)                                       AS total_churn_arr
FROM pbi_churn_by_account

ORDER BY method;


-- ===========================================================================
-- QUERY 2: ACCOUNT-LEVEL DETAIL — side-by-side with match flag
-- Run as a separate query.
-- ===========================================================================

WITH

exec_deck_churn AS (
    SELECT
        MASTER_CUSTOMER_ID,
        ACCOUNT_NAME,
        REGION,
        TERRITORY,
        ARR_RENEWAL,
        ARR_CHURN AS exec_deck_churn_arr
    FROM REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_CUSTOMER
    WHERE DATE_YQ = :target_quarter
      AND ARR_CHURN < 0
),

pbi_base AS (
    SELECT
        l.opportunity_id,
        o.id                                      AS opp_id,
        o.account_id,
        o.currency_rate_c,
        o.type,
        o.stage_name,
        o.renewal_baseline_c,
        o.renewal_final_amount_c,
        o.churn_type_c,
        o.churn_category_c,
        o.renewal_contract_start_date_c,
        l.annual_price_c
    FROM REPORTING.SALESFORCE.RAW_OPPORTUNITY_LINE_ITEM_REPORT l
    JOIN REPORTING.SALESFORCE.RAW_OPPORTUNITY_REPORT o
        ON o.id = l.opportunity_id
    WHERE l.is_deleted IS DISTINCT FROM TRUE
      AND COALESCE(o.exclude_from_cs_pipeline_c, 'No') <> 'Yes'
      AND o.renewal_contract_start_date_c IS NOT NULL
      AND YEAR(o.renewal_contract_start_date_c)::VARCHAR
            || '_Q'
            || QUARTER(o.renewal_contract_start_date_c)::VARCHAR
          = REPLACE(:target_quarter, '-', '_')
),

pbi_line_calc AS (
    SELECT
        b.*,
        DIV0(
            b.annual_price_c,
            SUM(b.annual_price_c) OVER (PARTITION BY b.opportunity_id)
        )                                                              AS ap_spread_pct,
        CASE
            WHEN b.type = 'Renewal - Downgrade'
             AND b.stage_name IN ('Closed Won', 'Closed Won - Finance')
            THEN DIV0(b.renewal_baseline_c,     b.currency_rate_c)
               - DIV0(b.renewal_final_amount_c, b.currency_rate_c)
            ELSE 0
        END                                                            AS downgrade_amount,
        CASE
            WHEN b.stage_name = 'Closed Lost'
            THEN DIV0(b.renewal_final_amount_c, b.currency_rate_c)
            ELSE 0
        END                                                            AS renewal_final_amount_cl
    FROM pbi_base b
),

pbi_line_churn AS (
    SELECT
        account_id,
        opportunity_id,
        churn_type_c,
        stage_name,
        type,
        (ap_spread_pct * downgrade_amount)
            + (ap_spread_pct * renewal_final_amount_cl)               AS total_churn
    FROM pbi_line_calc
),

pbi_churn_by_account AS (
    SELECT
        account_id,
        SUM(total_churn) * -1                                         AS pbi_churn_arr,
        -- Breakdown for diagnostic purposes
        SUM(CASE WHEN stage_name = 'Closed Lost' THEN total_churn ELSE 0 END) * -1   AS pbi_closed_lost_arr,
        SUM(CASE WHEN type = 'Renewal - Downgrade' THEN total_churn ELSE 0 END) * -1 AS pbi_downgrade_arr,
        COUNT(DISTINCT opportunity_id)                                 AS pbi_opp_count
    FROM pbi_line_churn
    WHERE total_churn != 0
    GROUP BY account_id
)

-- ---------------------------------------------------------------------------
-- RESULT 2: Account-level comparison with match status
-- ---------------------------------------------------------------------------
SELECT
    COALESCE(ed.MASTER_CUSTOMER_ID, pbi.account_id)                   AS account_id,
    ed.ACCOUNT_NAME,
    ed.REGION,
    ed.TERRITORY,

    -- Both methods (negative = churn)
    ROUND(ed.exec_deck_churn_arr, 0)                                   AS exec_deck_churn_arr,
    ROUND(pbi.pbi_churn_arr, 0)                                        AS pbi_churn_arr,

    -- PBI breakdown (diagnostic)
    ROUND(pbi.pbi_closed_lost_arr, 0)                                  AS pbi_closed_lost_component,
    ROUND(pbi.pbi_downgrade_arr, 0)                                    AS pbi_downgrade_component,
    pbi.pbi_opp_count,

    -- Delta: positive = EXEC_DECK shows more churn; negative = PBI shows more
    ROUND(
        COALESCE(ed.exec_deck_churn_arr, 0)
        - COALESCE(pbi.pbi_churn_arr, 0)
    , 0)                                                               AS delta_arr,

    -- Match status
    CASE
        WHEN ed.MASTER_CUSTOMER_ID IS NULL           THEN 'PBI Only — not in EXEC_DECK'
        WHEN pbi.account_id IS NULL                  THEN 'EXEC_DECK Only — not in PBI'
        WHEN ABS(
                COALESCE(ed.exec_deck_churn_arr, 0)
                - COALESCE(pbi.pbi_churn_arr, 0)
             ) < 100                                 THEN 'Match (< $100 diff)'
        WHEN ABS(
                COALESCE(ed.exec_deck_churn_arr, 0)
                - COALESCE(pbi.pbi_churn_arr, 0)
             ) / NULLIF(ABS(ed.exec_deck_churn_arr), 0) < 0.02
                                                     THEN 'Close (< 2% diff)'
        ELSE 'Mismatch'
    END                                                                AS match_status

FROM exec_deck_churn ed
FULL OUTER JOIN pbi_churn_by_account pbi
    ON pbi.account_id = ed.MASTER_CUSTOMER_ID

ORDER BY ABS(COALESCE(ed.exec_deck_churn_arr, 0) - COALESCE(pbi.pbi_churn_arr, 0)) DESC NULLS LAST;
