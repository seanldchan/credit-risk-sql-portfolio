-- ============================================================
-- 00_data_quality.sql
-- Purpose : Validate raw data before any analysis.
-- Dataset : credit_risk_dataset_2 (~32,000 consumer loans)
-- ============================================================

-- SECTION 1: Row count & basic completeness

SELECT COUNT(*) AS total_rows
FROM credit_risk_dataset_2;

-- Null counts across every column
-- I dentify which features will need imputation or exclusion
SELECT
    SUM(CASE WHEN person_age               IS NULL THEN 1 ELSE 0 END) AS null_person_age,
    SUM(CASE WHEN person_income            IS NULL THEN 1 ELSE 0 END) AS null_person_income,
    SUM(CASE WHEN person_home_ownership    IS NULL THEN 1 ELSE 0 END) AS null_home_ownership,
    SUM(CASE WHEN person_emp_length        IS NULL THEN 1 ELSE 0 END) AS null_emp_length,
    SUM(CASE WHEN loan_intent              IS NULL THEN 1 ELSE 0 END) AS null_loan_intent,
    SUM(CASE WHEN loan_grade               IS NULL THEN 1 ELSE 0 END) AS null_loan_grade,
    SUM(CASE WHEN loan_amnt                IS NULL THEN 1 ELSE 0 END) AS null_loan_amnt,
    SUM(CASE WHEN loan_int_rate            IS NULL THEN 1 ELSE 0 END) AS null_loan_int_rate,
    SUM(CASE WHEN loan_status              IS NULL THEN 1 ELSE 0 END) AS null_loan_status,
    SUM(CASE WHEN loan_percent_income      IS NULL THEN 1 ELSE 0 END) AS null_loan_pct_income,
    SUM(CASE WHEN cb_person_default_on_file IS NULL THEN 1 ELSE 0 END) AS null_default_on_file,
    SUM(CASE WHEN cb_person_cred_hist_length IS NULL THEN 1 ELSE 0 END) AS null_cred_hist_length
FROM credit_risk_dataset_2;


-- SECTION 2: Range & plausibility checks

-- Ages outside 18–99 are almost certainly data errors
-- Flag for exclusion when conducting feature engineering 

SELECT
    COUNT(*) AS implausible_age_count,
    MIN(person_age) AS min_age,
    MAX(person_age) AS max_age
FROM credit_risk_dataset_2
WHERE person_age < 18 OR person_age > 99;

-- Employment length cannot exceed working life (age - 16 as a floor)
-- Borrowers where emp_length > age - 16 suggest data entry errors

SELECT COUNT(*) AS implausible_emp_length_count
FROM credit_risk_dataset_2
WHERE person_emp_length > (person_age - 16);

-- Zero or negative income / loan amount — not analytically usable
SELECT
    SUM(CASE WHEN person_income <= 0 THEN 1 ELSE 0 END) AS zero_neg_income,
    SUM(CASE WHEN loan_amnt     <= 0 THEN 1 ELSE 0 END) AS zero_neg_loan_amnt,
    SUM(CASE WHEN loan_int_rate <= 0 THEN 1 ELSE 0 END) AS zero_neg_int_rate
FROM credit_risk_dataset_2;

-- Extreme income outliers. Consumer lending dataset should not
-- contain multi-million incomes; flag the top 0.1% for review

SELECT
    MAX(person_income)                                            AS max_income,
    SUBSTRING_INDEX(
        SUBSTRING_INDEX(
            GROUP_CONCAT(person_income ORDER BY person_income SEPARATOR ','),
            ',',
            CEIL(0.999 * COUNT(*))
        ),
        ',', -1
    ) AS p99_9_income
FROM credit_risk_dataset_2;

-- loan_percent_income sanity: should be loan_amnt / person_income
-- a large discrepancy would suggest the column is stored as a ratio (e.g. 0.15)
-- rather than a percentage (15). Confirm the scale.
SELECT
    ROUND(AVG(CAST(loan_percent_income AS DECIMAL(6,4))), 4) AS avg_stored_value,
    ROUND(AVG(CAST(loan_amnt AS DECIMAL) / NULLIF(person_income, 0)), 4) AS avg_derived_ratio
FROM credit_risk_dataset_2;

-- checking whether loan_percent_income is 0.15 or 15 -- matters for any ratio features later
-- if these match, it's already a ratio. if derived is ~100x smaller, it's stored as percentage


-- SECTION 3: Categorical value audits

-- loan_status should be binary (0 = performing, 1 = default)
SELECT DISTINCT loan_status
FROM credit_risk_dataset_2
ORDER BY loan_status;

-- cb_person_default_on_file should only be 'Y' / 'N'
SELECT cb_person_default_on_file, COUNT(*) AS row_count
FROM credit_risk_dataset_2
GROUP BY cb_person_default_on_file;

-- loan_grade expected values: A–G
SELECT loan_grade, COUNT(*) AS row_count
FROM credit_risk_dataset_2
GROUP BY loan_grade
ORDER BY loan_grade;

-- home_ownership — confirm expected categories
SELECT person_home_ownership, COUNT(*) AS row_count
FROM credit_risk_dataset_2
GROUP BY person_home_ownership
ORDER BY row_count DESC;

-- loan_intent — confirm expected categories
SELECT loan_intent, COUNT(*) AS row_count
FROM credit_risk_dataset_2
GROUP BY loan_intent
ORDER BY row_count DESC;


-- SECTION 4: Internal consistency checks


-- Grade vs interest rate correlation — Grade A should have the
-- lowest rates; if not, the grading column is unreliable as a
-- risk proxy and downstream segment analysis is redundant.
-- Confirm if loan_grade is usable as a risk signal.
SELECT
    loan_grade,
    COUNT(*)                                    AS total_loans,
    ROUND(MIN(loan_int_rate), 2)                AS min_rate,
    ROUND(AVG(loan_int_rate), 2)                AS avg_rate,
    ROUND(MAX(loan_int_rate), 2)                AS max_rate
FROM credit_risk_dataset_2
WHERE loan_int_rate > 0
GROUP BY loan_grade
ORDER BY loan_grade;

-- Grade vs observed default rate — higher grades should default more.
-- If Grade A defaults more than Grade F, the target variable or grading
-- is corrupted
SELECT
    loan_grade,
    ROUND(AVG(loan_status) * 100, 2) AS default_rate_pct
FROM credit_risk_dataset_2
GROUP BY loan_grade
ORDER BY loan_grade;

-- SECTION 5: Data quality summary flag

-- Consolidates key exclusion criteria into a single CTE that
-- 01_feature_engineering.sql can reference or mirror

WITH quality_flags AS (
    SELECT
        *,
        CASE
            WHEN person_income <= 0                    THEN 'EXCLUDE: zero income'
            WHEN loan_amnt <= 0                        THEN 'EXCLUDE: zero loan amount'
            WHEN loan_int_rate <= 0                    THEN 'EXCLUDE: zero interest rate'
            WHEN person_age < 18 OR person_age > 99   THEN 'EXCLUDE: implausible age'
            WHEN person_emp_length > (person_age - 16) THEN 'FLAG: emp length > working life'
            ELSE 'PASS'
        END AS quality_flag
    FROM credit_risk_dataset_2
)
SELECT
    quality_flag,
    COUNT(*) AS row_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM quality_flags
GROUP BY quality_flag
ORDER BY row_count DESC;

-- Finding: rows flagged EXCLUDE will be filtered in the feature view.
-- FLAG rows are retained but noted, they may warrant sensitivity analysis.