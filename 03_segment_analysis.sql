-- ============================================================
-- 03_segment_analysis.sql
-- Purpose : Segment the portfolio by key risk dimensions and
--           validate that derived features (DTI band, risk tier)
--           actually discriminate default risk.
--           A feature that doesn't separate default rates is not
--           analytically useful — every band result is checked.
-- ============================================================


-- ------------------------------------------------------------
-- 3.1 Loan grade — the lender's own risk classification
-- ------------------------------------------------------------
-- Finding: Grade should monotonically worsen from A → G on both
-- default rate and interest rate. If not, the grading model is
-- miscalibrated — a significant finding worth calling out.

SELECT
    loan_grade,
    COUNT(*)                                        AS total_loans,
    SUM(loan_amnt)                                  AS total_exposure,
    ROUND(AVG(loan_status) * 100, 2)                AS default_rate_pct,
    ROUND(AVG(loan_int_rate), 2)                    AS avg_interest_rate_pct,
    -- Rate spread vs Grade A (pricing adequacy check)
    ROUND(AVG(loan_int_rate) - MIN(AVG(loan_int_rate)) OVER (), 2)
                                                    AS rate_spread_vs_best_grade
FROM vw_credit_risk_features
GROUP BY loan_grade
ORDER BY loan_grade;


-- ------------------------------------------------------------
-- 3.2 DTI band — affordability signal
-- ------------------------------------------------------------
-- Finding: each DTI band should show materially higher default
-- rates than the one below it. If Low DTI and Moderate DTI
-- default at similar rates, the 20% threshold is wrong.

SELECT
    dti_band,
    COUNT(*)                                        AS borrowers,
    ROUND(AVG(loan_status) * 100, 2)                AS default_rate_pct,
    ROUND(AVG(debt_to_income_ratio), 4)             AS avg_dti,
    ROUND(AVG(loan_int_rate), 2)                    AS avg_interest_rate_pct
FROM vw_credit_risk_features
GROUP BY dti_band
ORDER BY avg_dti;


-- ------------------------------------------------------------
-- 3.3 Prior default flag — bureau history signal
-- ------------------------------------------------------------
-- Finding: borrowers with a prior default on file should show
-- a substantially elevated default rate. If the delta is small
-- (<5 percentage points), the bureau flag adds limited predictive
-- value and its weight in the risk tier should be reviewed.

SELECT
    CASE prior_default_flag WHEN 1 THEN 'Prior Default: Yes' ELSE 'Prior Default: No' END
                                                    AS prior_default,
    COUNT(*)                                        AS borrowers,
    ROUND(AVG(loan_status) * 100, 2)                AS default_rate_pct,
    ROUND(AVG(debt_to_income_ratio), 4)             AS avg_dti,
    ROUND(AVG(loan_amnt), 0)                        AS avg_loan_amnt
FROM vw_credit_risk_features
GROUP BY prior_default_flag
ORDER BY prior_default_flag DESC;


-- ------------------------------------------------------------
-- 3.4 Credit history length — thin-file risk
-- ------------------------------------------------------------
-- Finding: thin-file borrowers (<2yr history) are under-observed
-- by credit bureaus and typically show higher default rates.
-- This is a standard overlay consideration in consumer lending policy.

SELECT
    credit_history_band,
    COUNT(*)                                        AS borrowers,
    ROUND(AVG(loan_status) * 100, 2)                AS default_rate_pct,
    ROUND(AVG(cb_person_cred_hist_length), 1)       AS avg_history_years,
    ROUND(AVG(loan_int_rate), 2)                    AS avg_interest_rate_pct
FROM vw_credit_risk_features
GROUP BY credit_history_band, cb_person_cred_hist_length
-- Re-aggregate on band only
-- (workaround for engines that don't allow expression in GROUP BY HAVING)
ORDER BY avg_history_years;

-- Cleaner version for engines supporting GROUP BY on derived column alias:
SELECT
    credit_history_band,
    COUNT(*)                                        AS borrowers,
    ROUND(AVG(loan_status) * 100, 2)                AS default_rate_pct,
    ROUND(AVG(cb_person_cred_hist_length), 1)       AS avg_history_years
FROM vw_credit_risk_features
GROUP BY credit_history_band
ORDER BY avg_history_years;


-- ------------------------------------------------------------
-- 3.5 Composite risk tier — validation
-- ------------------------------------------------------------
-- This is critical: if the four tiers do NOT produce clearly
-- ordered default rates, the composite logic in
-- 01_feature_engineering.sql must be revised before it is used
-- in any business-facing output.

SELECT
    risk_tier,
    COUNT(*)                                        AS borrowers,
    ROUND(AVG(loan_status) * 100, 2)                AS default_rate_pct,
    ROUND(AVG(debt_to_income_ratio), 4)             AS avg_dti,
    ROUND(AVG(loan_int_rate), 2)                    AS avg_interest_rate_pct,
    SUM(loan_amnt)                                  AS total_exposure,
    ROUND(SUM(loan_amnt) * 100.0 / SUM(SUM(loan_amnt)) OVER (), 2)
                                                    AS pct_of_total_exposure
FROM vw_credit_risk_features
GROUP BY risk_tier
ORDER BY default_rate_pct DESC;

-- Finding to record after running:
-- Tier 1 default rate: ____%
-- Tier 2 default rate: ____%
-- Tier 3 default rate: ____%
-- Tier 4 default rate: ____%
-- If tiers are not ordered, revisit threshold logic in 01_.


-- ------------------------------------------------------------
-- 3.6 Age band — demographic risk profile
-- ------------------------------------------------------------
-- Finding: younger borrowers (18-24) typically show higher default
-- rates due to shorter credit histories and lower income stability.

SELECT
    age_band,
    COUNT(*)                                        AS borrowers,
    ROUND(AVG(loan_status) * 100, 2)                AS default_rate_pct,
    ROUND(AVG(person_income), 0)                    AS avg_income,
    ROUND(AVG(debt_to_income_ratio), 4)             AS avg_dti
FROM vw_credit_risk_features
GROUP BY age_band
ORDER BY age_band;