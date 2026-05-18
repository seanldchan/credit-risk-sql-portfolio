-- ============================================================
-- 02_portfolio_analysis.sql
-- Purpose : Portfolio-level overview — total exposure, default
--           rate, interest rate adequacy, and concentration.
--           These are the headline numbers a credit committee
--           or risk manager would review first.
-- ============================================================


-- ------------------------------------------------------------
-- 2.1 Portfolio headline metrics
-- ------------------------------------------------------------
-- Finding: establishes baseline PD for the full book.
-- A portfolio default rate above ~15% for unsecured consumer
-- lending would be considered high-risk by most UK/US lenders.

SELECT
    COUNT(*)                                        AS total_loans,
    SUM(loan_amnt)                                  AS total_exposure,
    ROUND(AVG(loan_int_rate), 2)                    AS avg_interest_rate_pct,
    ROUND(AVG(loan_status) * 100, 2)                AS portfolio_default_rate_pct,
    ROUND(SUM(loan_status * 0.45 * loan_amnt), 0)   AS total_expected_loss_proxy,
    ROUND(
        SUM(loan_status * 0.45 * loan_amnt)
        / NULLIF(SUM(loan_amnt), 0) * 100
    , 2)                                            AS expected_loss_rate_pct
FROM vw_credit_risk_features;


-- ------------------------------------------------------------
-- 2.2 Exposure by loan intent — concentration risk
-- ------------------------------------------------------------
-- Finding: which purposes drive the most absolute exposure and
-- whether high-intent segments are also high-default.
-- A lender over-indexed in one category (e.g. debt consolidation)
-- is exposed to correlated default risk in a downturn.

SELECT
    loan_intent,
    COUNT(*)                                                AS total_loans,
    SUM(loan_amnt)                                          AS total_exposure,
    ROUND(SUM(loan_amnt) * 100.0 / SUM(SUM(loan_amnt)) OVER (), 2)
                                                            AS pct_of_total_exposure,
    ROUND(AVG(loan_status) * 100, 2)                        AS default_rate_pct,
    ROUND(AVG(loan_int_rate), 2)                            AS avg_interest_rate_pct
FROM vw_credit_risk_features
GROUP BY loan_intent
ORDER BY total_exposure DESC;


-- ------------------------------------------------------------
-- 2.3 Loan size concentration (top-decile exposure)
-- ------------------------------------------------------------
-- Finding: in lending portfolios, the top 10% of loans by size
-- often account for >30% of total exposure. This matters for
-- capital adequacy — large-ticket defaults are disproportionately
-- damaging.

WITH loan_deciles AS (
    SELECT
        loan_amnt,
        loan_status,
        NTILE(10) OVER (ORDER BY loan_amnt) AS size_decile
    FROM vw_credit_risk_features
)
SELECT
    size_decile,
    COUNT(*)                                                AS total_loans,
    MIN(loan_amnt)                                          AS min_loan_amnt,
    MAX(loan_amnt)                                          AS max_loan_amnt,
    SUM(loan_amnt)                                          AS total_exposure,
    ROUND(SUM(loan_amnt) * 100.0 / SUM(SUM(loan_amnt)) OVER (), 2)
                                                            AS pct_of_total_exposure,
    ROUND(AVG(loan_status) * 100, 2)                        AS default_rate_pct
FROM loan_deciles
GROUP BY size_decile
ORDER BY size_decile;

-- Finding to look for: does default_rate_pct rise with size_decile?
-- If larger loans default more, pricing and LTV limits need review.


-- ------------------------------------------------------------
-- 2.4 Home ownership vs default — collateral context
-- ------------------------------------------------------------
-- Finding: mortgage holders typically have lower unsecured default
-- rates (established financial behaviour, more to lose).
-- Renters / "OTHER" categories often show elevated default.

SELECT
    person_home_ownership,
    COUNT(*)                                        AS total_loans,
    ROUND(AVG(loan_status) * 100, 2)                AS default_rate_pct,
    ROUND(AVG(debt_to_income_ratio), 4)             AS avg_dti,
    ROUND(AVG(loan_int_rate), 2)                    AS avg_interest_rate_pct
FROM vw_credit_risk_features
GROUP BY person_home_ownership
ORDER BY default_rate_pct DESC;