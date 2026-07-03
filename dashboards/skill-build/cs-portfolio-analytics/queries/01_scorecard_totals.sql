-- =============================================================================
-- 01_scorecard_totals.sql
-- Global Renewal Scorecard — Totals
-- =============================================================================
-- Description : Returns renewal KPIs (count, ARR, churn ARR, renewal rate)
--               for the target quarter, prior quarter, and same quarter prior
--               year, together with QoQ and YoY deltas and a trend indicator.
--
-- Source      : REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_CUSTOMER
--               Grain: MASTER_CUSTOMER_ID × DATE_YQ
--
-- Parameters  :
--   :target_quarter  VARCHAR  Target quarter in 'YYYY-QN' format, e.g. '2026-Q1'
--   :target_arr      NUMBER   Full-year ARR target (used to compute vs-target %)
--
-- Renewal Rate formula : (ARR_RENEWAL + ARR_CHURN) / ARR_RENEWAL
--   ARR_CHURN is always stored as a negative number.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Helper: derive adjacent quarters from :target_quarter
--   Prior quarter : Q1 → (year-1)-Q4 | Q2→Q1 | Q3→Q2 | Q4→Q3
--   YoY quarter   : same Q, year - 1
-- ---------------------------------------------------------------------------

WITH

-- Raw quarter-number and year extracted from the target parameter
qtr_parts AS (
    SELECT
        :target_quarter                                              AS target_qtr,
        CAST(LEFT(:target_quarter, 4)  AS INT)                      AS yr,
        CAST(RIGHT(:target_quarter, 1) AS INT)                      AS qn
),

-- Derive the three reference quarter labels
qtr_labels AS (
    SELECT
        target_qtr,
        yr,
        qn,
        -- Prior quarter
        CASE
            WHEN qn = 1 THEN (yr - 1)::VARCHAR || '-Q4'
            ELSE yr::VARCHAR || '-Q' || (qn - 1)::VARCHAR
        END                                                          AS prior_qtr,
        -- Same quarter prior year
        (yr - 1)::VARCHAR || '-Q' || qn::VARCHAR                    AS yoy_qtr
    FROM qtr_parts
),

-- ---------------------------------------------------------------------------
-- Aggregate EXEC_DECK_CUS per quarter
-- ---------------------------------------------------------------------------
base AS (
    SELECT
        DATE_YQ,
        COUNT(DISTINCT CASE WHEN ARR_RENEWAL > 0 THEN MASTER_CUSTOMER_ID END)  AS renewal_count,
        SUM(ARR_RENEWAL)                                                         AS renewal_arr,
        COUNT(DISTINCT CASE WHEN ARR_CHURN  < 0 THEN MASTER_CUSTOMER_ID END)   AS churn_count,
        SUM(ARR_CHURN)                                                           AS churn_arr,
        -- Renewal Rate: (ARR_RENEWAL + ARR_CHURN) / ARR_RENEWAL
        CASE
            WHEN SUM(ARR_RENEWAL) = 0 THEN NULL
            ELSE (SUM(ARR_RENEWAL) + SUM(ARR_CHURN)) / NULLIF(SUM(ARR_RENEWAL), 0)
        END                                                                      AS renewal_rate
    FROM REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_CUSTOMER
    GROUP BY DATE_YQ
),

-- ---------------------------------------------------------------------------
-- Slice per period
-- ---------------------------------------------------------------------------
current_qtr AS (
    SELECT
        'current'           AS period,
        b.DATE_YQ,
        b.renewal_count,
        b.renewal_arr,
        b.churn_count,
        b.churn_arr,
        b.renewal_rate
    FROM base b
    JOIN qtr_labels l ON b.DATE_YQ = l.target_qtr
),

prior_qtr AS (
    SELECT
        'prior'             AS period,
        b.DATE_YQ,
        b.renewal_count,
        b.renewal_arr,
        b.churn_count,
        b.churn_arr,
        b.renewal_rate
    FROM base b
    JOIN qtr_labels l ON b.DATE_YQ = l.prior_qtr
),

yoy_qtr AS (
    SELECT
        'yoy'               AS period,
        b.DATE_YQ,
        b.renewal_count,
        b.renewal_arr,
        b.churn_count,
        b.churn_arr,
        b.renewal_rate
    FROM base b
    JOIN qtr_labels l ON b.DATE_YQ = l.yoy_qtr
),

-- ---------------------------------------------------------------------------
-- ARR target passthrough
-- ---------------------------------------------------------------------------
targets AS (
    SELECT :target_arr AS arr_target
),

-- ---------------------------------------------------------------------------
-- Combine all periods into a single wide row
-- ---------------------------------------------------------------------------
combined AS (
    SELECT
        c.DATE_YQ                                                           AS current_quarter,
        p.DATE_YQ                                                           AS prior_quarter,
        y.DATE_YQ                                                           AS yoy_quarter,

        -- Renewal counts
        c.renewal_count                                                     AS current_renewal_count,
        p.renewal_count                                                     AS prior_renewal_count,
        y.renewal_count                                                     AS yoy_renewal_count,

        -- Renewal ARR
        c.renewal_arr                                                       AS current_renewal_arr,
        p.renewal_arr                                                       AS prior_renewal_arr,
        y.renewal_arr                                                       AS yoy_renewal_arr,

        -- Churn counts
        c.churn_count                                                       AS current_churn_count,
        p.churn_count                                                       AS prior_churn_count,
        y.churn_count                                                       AS yoy_churn_count,

        -- Churn ARR
        c.churn_arr                                                         AS current_churn_arr,
        p.churn_arr                                                         AS prior_churn_arr,
        y.churn_arr                                                         AS yoy_churn_arr,

        -- Renewal rates
        c.renewal_rate                                                      AS current_renewal_rate,
        p.renewal_rate                                                      AS prior_renewal_rate,
        y.renewal_rate                                                      AS yoy_renewal_rate,

        -- ARR target
        t.arr_target

    FROM       current_qtr c
    CROSS JOIN prior_qtr   p
    CROSS JOIN yoy_qtr     y
    CROSS JOIN targets     t
)

-- ---------------------------------------------------------------------------
-- Final output: add deltas, percentage changes, and trend indicator
-- ---------------------------------------------------------------------------
SELECT
    current_quarter,
    prior_quarter,
    yoy_quarter,

    -- ---- Counts ----
    current_renewal_count,
    prior_renewal_count,
    yoy_renewal_count,
    (current_renewal_count - prior_renewal_count)                           AS qoq_renewal_count_delta,
    (current_renewal_count - yoy_renewal_count)                             AS yoy_renewal_count_delta,

    -- ---- Renewal ARR ----
    ROUND(current_renewal_arr, 2)                                           AS current_renewal_arr,
    ROUND(prior_renewal_arr,   2)                                           AS prior_renewal_arr,
    ROUND(yoy_renewal_arr,     2)                                           AS yoy_renewal_arr,
    ROUND(current_renewal_arr - prior_renewal_arr, 2)                       AS qoq_renewal_arr_delta,
    ROUND(current_renewal_arr - yoy_renewal_arr,   2)                       AS yoy_renewal_arr_delta,

    -- ---- Churn ARR ----
    ROUND(current_churn_arr, 2)                                             AS current_churn_arr,
    ROUND(prior_churn_arr,   2)                                             AS prior_churn_arr,
    ROUND(yoy_churn_arr,     2)                                             AS yoy_churn_arr,
    ROUND(current_churn_arr - prior_churn_arr, 2)                           AS qoq_churn_arr_delta,
    ROUND(current_churn_arr - yoy_churn_arr,   2)                           AS yoy_churn_arr_delta,

    -- ---- Renewal Rates ----
    ROUND(current_renewal_rate, 4)                                          AS current_renewal_rate,
    ROUND(prior_renewal_rate,   4)                                          AS prior_renewal_rate,
    ROUND(yoy_renewal_rate,     4)                                          AS yoy_renewal_rate,
    ROUND(current_renewal_rate - prior_renewal_rate, 4)                     AS qoq_rr_delta,
    ROUND(current_renewal_rate - yoy_renewal_rate,   4)                     AS yoy_rr_delta,

    -- ---- % changes (on renewal rate) ----
    CASE
        WHEN prior_renewal_rate = 0 OR prior_renewal_rate IS NULL THEN NULL
        ELSE ROUND((current_renewal_rate - prior_renewal_rate) / ABS(prior_renewal_rate), 4)
    END                                                                     AS qoq_rr_pct_change,
    CASE
        WHEN yoy_renewal_rate = 0 OR yoy_renewal_rate IS NULL THEN NULL
        ELSE ROUND((current_renewal_rate - yoy_renewal_rate) / ABS(yoy_renewal_rate), 4)
    END                                                                     AS yoy_rr_pct_change,

    -- ---- vs Target ----
    arr_target,
    CASE
        WHEN arr_target = 0 OR arr_target IS NULL THEN NULL
        ELSE ROUND(current_renewal_arr / arr_target, 4)
    END                                                                     AS vs_target_pct,

    -- ---- Trend indicator ----
    -- Threshold: QoQ RR improvement >= +1pp = UP, <= -1pp = DOWN, else ON_TARGET
    CASE
        WHEN (current_renewal_rate - prior_renewal_rate) >  0.01 THEN 'UP'
        WHEN (current_renewal_rate - prior_renewal_rate) < -0.01 THEN 'DOWN'
        ELSE 'ON_TARGET'
    END                                                                     AS trend_indicator

FROM combined
;
