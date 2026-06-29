-- 01_feature_engineering.sql
-- Build the analytical base view used by all
--    ownstream queries. Applies validated exclusions
--           from 00_data_quality and derives features
--           with business rationale for each.
-- ============================================================


CREATE OR REPLACE VIEW vw_credit_risk_features AS
SELECT


    -- Raw columns (pass-through)
    
    person_age,
    person_income,
    person_home_ownership,
    person_emp_length,
    loan_intent,
    loan_grade,
    loan_amnt,
    loan_int_rate,
    loan_status,                         -- 0 = performing, 1 = defaulted
    cb_person_default_on_file,
    cb_person_cred_hist_length,


    -- Derived: income ratio (loan_percent_income normalised)
    -- Stored as a ratio (0–1); confirmed in 00_data_quality.sql

    CAST(loan_percent_income AS DECIMAL(5, 4)) AS debt_to_income_ratio,


    -- Derived: Estimated Expected Loss proxy
    -- EL = PD × LGD × EAD
    -- PD  = loan_status (observed; 1 if defaulted)
    -- LGD = assumed 45% (Basel II)
    -- EAD = loan_amnt
    -- For portfolio-level analysis, substitute AVG(loan_status)

    ROUND(loan_status * 0.45 * loan_amnt, 2) AS expected_loss_proxy,


    -- Band: age
    CASE
        WHEN person_age < 25             THEN '18-24'
        WHEN person_age BETWEEN 25 AND 34 THEN '25-34'
        WHEN person_age BETWEEN 35 AND 49 THEN '35-49'
        ELSE '50+'
    END AS age_band,


    -- Band: income
    -- Thresholds approximate UK consumer lending segments;
    CASE
        WHEN person_income < 30000                       THEN 'Low (<30k)'
        WHEN person_income BETWEEN 30000 AND 70000       THEN 'Middle (30–70k)'
        WHEN person_income BETWEEN 70001 AND 120000      THEN 'High (70–120k)'
        ELSE 'Very High (120k+)'
    END AS income_band,

    -- Band: debt-to-income (DTI) — primary affordability signal
    -- Thresholds loosely follow FCA / mortgage affordability
    -- stress-test conventions adapted for unsecured lending.
    -- Low  ≤ 20%  : repayment is low relative to income
    -- Mod  ≤ 35%  : approaching stress threshold
    -- High ≤ 50%  : income significantly committed to debt
    -- Severe >50% : high probability of affordability failure
    
    CASE
        WHEN CAST(loan_percent_income AS DECIMAL(5, 4)) <= 0.20 THEN 'Low DTI'
        WHEN CAST(loan_percent_income AS DECIMAL(5, 4)) <= 0.35 THEN 'Moderate DTI'
        WHEN CAST(loan_percent_income AS DECIMAL(5, 4)) <= 0.50 THEN 'High DTI'
        ELSE 'Severe DTI'
    END AS dti_band,

    -- Flag: prior default on credit bureau file
    
    CASE
        WHEN cb_person_default_on_file = 'Y' THEN 1
        ELSE 0
    END AS prior_default_flag,

    -- Band: credit history length
    -- Thin-file borrowers (<2 yrs) are a distinct risk cohort
    -- in consumer credit; lenders typically apply overlays.

    CASE
        WHEN cb_person_cred_hist_length < 2  THEN 'Thin File (<2yr)'
        WHEN cb_person_cred_hist_length < 5  THEN 'Short (2–4yr)'
        WHEN cb_person_cred_hist_length < 10 THEN 'Established (5–9yr)'
        ELSE 'Long (10yr+)'
    END AS credit_history_band,

    -- Composite risk tier
    -- Combines the two strongest individual default predictors
    -- in the dataset (bureau default flag + DTI).
    
    -- show materially different default rates; if not, revise.

    CASE
        WHEN cb_person_default_on_file = 'Y'
             AND CAST(loan_percent_income AS DECIMAL(5, 4)) > 0.35
            THEN 'Tier 1 – High Risk'
        WHEN cb_person_default_on_file = 'Y'
             OR  CAST(loan_percent_income AS DECIMAL(5, 4)) > 0.35
            THEN 'Tier 2 – Elevated Risk'
        WHEN CAST(loan_percent_income AS DECIMAL(5, 4)) > 0.20
            THEN 'Tier 3 – Moderate Risk'
        ELSE 'Tier 4 – Low Risk'
    END AS risk_tier

FROM credit_risk_dataset_2

-- Exclusions validated in 00_data_quality.sql

WHERE person_income > 0
  AND loan_amnt > 0
  AND loan_int_rate > 0
  AND person_age BETWEEN 18 AND 99;