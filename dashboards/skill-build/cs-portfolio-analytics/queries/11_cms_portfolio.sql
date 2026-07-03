-- =============================================================================
-- FILE 11: CMS PORTFOLIO VIEW (CSM OPERATIONAL TABLE)
-- =============================================================================
-- Description : One row per CMS account; designed as an operational table for
--               CSMs to review their entire CMS book at a glance.
-- Parameters  : :target_quarter -- e.g. '2026-Q1'
-- Tables      : REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_CUSTOMER    (EXEC_DECK_CUS)
--               REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP (EXEC_DECK_PG)
--               REPORTING.ARR_SST.SST_REPORT                                (SST_REPORT)
--               REPORTING.GTM_ANALYTICS.RENEWAL_OPPORTUNITY                  (RENEWAL_OPP)
-- CMS products: Content Management PaaS, Content Management SaaS,
--               Content Management Addons, Content Management Platform,
--               Content Marketing Platform, Digital Asset Management,
--               Configured Commerce, Product Recommendations,
--               Content Recommendations, Commerce Connect Non-Retail
-- Author      : CS Analytics Toolkit
-- =============================================================================


-- ---------------------------------------------------------------------------
-- Step 1: Identify CMS customers from SST_REPORT for the target quarter
-- ---------------------------------------------------------------------------
WITH cms_product_groups AS (
    -- Canonical list of CMS-family product groups (EC + CMP families)
    SELECT col1 AS product_group
    FROM VALUES
        ('Content Management PaaS'),
        ('Content Management SaaS'),
        ('Content Management Addons'),
        ('Content Management Platform'),
        ('Content Marketing Platform'),
        ('Digital Asset Management'),
        ('Configured Commerce'),
        ('Product Recommendations'),
        ('Content Recommendations'),
        ('Commerce Connect Non-Retail')
),

cms_mcids AS (
    -- Distinct MCIDs that have at least one CMS product in the target quarter snapshot
    SELECT DISTINCT s.MASTER_CUSTOMER_ID
    FROM REPORTING.ARR_SST.SST_REPORT s
    INNER JOIN cms_product_groups pg ON s.UPDATED_PRODUCT_GROUP = pg.product_group
    WHERE
        s.NEW_PRODUCT_SOLUTION != 'EOL'
        AND DAY(s.SNAPSHOT_DATE) >= 28
        AND TO_CHAR(s.SNAPSHOT_DATE, 'YYYY') || '-Q' ||
            QUARTER(s.SNAPSHOT_DATE)::VARCHAR = :target_quarter
),

-- ---------------------------------------------------------------------------
-- Step 2: EXEC_DECK_CUS base — one row per CMS MCID for the target quarter
-- ---------------------------------------------------------------------------
cus_base AS (
    SELECT
        c.MASTER_CUSTOMER_ID,
        c.ACCOUNT_NAME,
        c.PRIMARY_CSM,
        c.REGION,
        c.TERRITORY,
        c.SFDC_SEGMENT,
        c.ARR_RENEWAL,
        c.ARR_CHURN,
        -- Renewal rate at account level
        DIV0(c.ARR_RENEWAL + c.ARR_CHURN, c.ARR_RENEWAL) AS renewal_rate,
        -- QBR status if field exists in EXEC_DECK_CUS (NULL if unavailable)
        CASE
            WHEN c.QBR_STATUS = 'Completed' THEN 'Yes'
            WHEN c.QBR_STATUS IS NULL        THEN NULL
            ELSE 'No'
        END AS qbr_completed,
        -- Revenue segment derived from ARR_RENEWAL
        CASE
            WHEN c.ARR_RENEWAL >= 500000  THEN 'Enterprise'
            WHEN c.ARR_RENEWAL >= 100000  THEN 'Mid-Market'
            WHEN c.ARR_RENEWAL >= 25000   THEN 'Commercial'
            ELSE                               'SMB'
        END AS revenue_segment
    FROM REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_CUSTOMER c
    INNER JOIN cms_mcids m ON c.MASTER_CUSTOMER_ID = m.MASTER_CUSTOMER_ID
    WHERE c.DATE_YQ = :target_quarter
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY c.MASTER_CUSTOMER_ID ORDER BY c.DATE_YQ DESC
    ) = 1
),

-- ---------------------------------------------------------------------------
-- Step 3: CMS product group list per MCID (from EXEC_DECK_PG, deduped)
-- ---------------------------------------------------------------------------
pg_cms AS (
    SELECT
        MASTER_CUSTOMER_ID,
        PRODUCT_GROUP_CLEANED,
        DATE_YM
    FROM REPORTING.GTM_ANALYTICS.EXEC_DECK_RENEWAL_RATES_PRODUCT_GROUP
    WHERE
        PRODUCT_GROUP_CLEANED IN (
            SELECT product_group FROM cms_product_groups
        )
        AND DATE_YQ = :target_quarter
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY MASTER_CUSTOMER_ID, PRODUCT_GROUP_CLEANED, DATE_YM
        ORDER BY DATE_YM DESC
    ) = 1
),

pg_agg AS (
    -- Comma-separated list of distinct CMS products per MCID
    SELECT
        MASTER_CUSTOMER_ID,
        LISTAGG(DISTINCT PRODUCT_GROUP_CLEANED, ', ')
            WITHIN GROUP (ORDER BY PRODUCT_GROUP_CLEANED) AS product_groups
    FROM pg_cms
    GROUP BY MASTER_CUSTOMER_ID
),

-- ---------------------------------------------------------------------------
-- Step 4: Sol Type (Single vs Multi) from SST_REPORT
-- ---------------------------------------------------------------------------
sst_sol_type AS (
    SELECT
        MASTER_CUSTOMER_ID,
        COUNT(DISTINCT UPDATED_PRODUCT_GROUP)       AS cms_product_count,
        IFF(COUNT(DISTINCT UPDATED_PRODUCT_GROUP) > 1, 'Multi', 'Single') AS sol_type
    FROM REPORTING.ARR_SST.SST_REPORT s
    INNER JOIN cms_product_groups pg ON s.UPDATED_PRODUCT_GROUP = pg.product_group
    WHERE
        s.NEW_PRODUCT_SOLUTION != 'EOL'
        AND DAY(s.SNAPSHOT_DATE) >= 28
        AND TO_CHAR(s.SNAPSHOT_DATE, 'YYYY') || '-Q' ||
            QUARTER(s.SNAPSHOT_DATE)::VARCHAR = :target_quarter
    GROUP BY MASTER_CUSTOMER_ID
),

-- ---------------------------------------------------------------------------
-- Step 5: Contract dates and pipeline stage from RENEWAL_OPP
--         Rule: MAX(RENEWAL_FINAL_AMOUNT_USD) per MCID + OPPORTUNITY_ID
-- ---------------------------------------------------------------------------
opp_deduped AS (
    SELECT
        MASTER_CUSTOMER_ID,
        OPPORTUNITY_ID,
        OPPORTUNITY_STAGE,
        CONTRACT_START_DATE,
        CLOSE_DATE,
        MAX(RENEWAL_FINAL_AMOUNT_USD) AS opp_arr
    FROM REPORTING.GTM_ANALYTICS.RENEWAL_OPPORTUNITY
    WHERE DATE_YQ = :target_quarter
    GROUP BY
        MASTER_CUSTOMER_ID,
        OPPORTUNITY_ID,
        OPPORTUNITY_STAGE,
        CONTRACT_START_DATE,
        CLOSE_DATE
),

-- Latest open opportunity per MCID (for pipeline stage and renewal date)
opp_latest AS (
    SELECT
        MASTER_CUSTOMER_ID,
        OPPORTUNITY_STAGE                   AS pipeline_stage,
        CONTRACT_START_DATE                 AS contract_start_date,
        CLOSE_DATE                          AS renewal_date,
        opp_arr
    FROM opp_deduped
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY MASTER_CUSTOMER_ID
        ORDER BY CLOSE_DATE DESC, opp_arr DESC
    ) = 1
)

-- ---------------------------------------------------------------------------
-- Final SELECT: Assemble the CMS Portfolio operational table
-- ---------------------------------------------------------------------------
SELECT
    cb.PRIMARY_CSM                          AS cms_manager,
    cb.MASTER_CUSTOMER_ID,
    cb.ACCOUNT_NAME,
    ol.contract_start_date,
    ol.renewal_date,
    cb.REGION,
    cb.TERRITORY,
    cb.SFDC_SEGMENT,
    cb.revenue_segment,
    pa.product_groups,
    COALESCE(st.sol_type, 'Single')         AS sol_type,
    cb.qbr_completed,
    cb.ARR_RENEWAL                          AS arr_renewal,
    cb.renewal_rate,
    ol.pipeline_stage
FROM cus_base cb
LEFT JOIN pg_agg      pa ON cb.MASTER_CUSTOMER_ID = pa.MASTER_CUSTOMER_ID
LEFT JOIN sst_sol_type st ON cb.MASTER_CUSTOMER_ID = st.MASTER_CUSTOMER_ID
LEFT JOIN opp_latest   ol ON cb.MASTER_CUSTOMER_ID = ol.MASTER_CUSTOMER_ID
ORDER BY
    cb.PRIMARY_CSM ASC,
    cb.ARR_RENEWAL DESC;
