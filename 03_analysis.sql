/* =====================================================================
   BerkaBank - 03_analysis.sql
   Part C: business questions (SQL Server)
   Run AFTER 01_setup.sql and 02_cleaning.sql
   Each question: the query, then the finding as a comment.
   ===================================================================== */

USE BerkaBank;
GO


/* =====================================================================
   C1. How many accounts were opened each year?
   ===================================================================== */
SELECT YEAR([date]) AS open_year,
       COUNT(*)     AS accounts
FROM account
GROUP BY YEAR([date])
ORDER BY open_year;
/* Finding:
   Account openings dropped by 61% from 1993 (1,139) to 1994 (439), then recovered and
   peaked in 1996 (1,363) before falling to 898 in 1997. The high 1993 figure may include
   existing accounts migrated into the system in the first year of data. */
GO


/* =====================================================================
   C2. Number of clients by gender and age group
   ===================================================================== */
SELECT gender,
       age_group,
       COUNT(*) AS clients
FROM clients
GROUP BY gender, age_group
ORDER BY gender,
         CASE age_group WHEN 'Under 30' THEN 1
                        WHEN '30-49'    THEN 2
                        ELSE 3 END;
/* Finding:
   The customer base is gender-balanced (F 2,645 = 49%, M 2,724 = 51%) but skews older:
   50+ is the largest group in both genders (2,163 = 40% of all clients), while Under 30
   is the smallest (1,282 = 24%). There is an opportunity to attract younger customers. */
GO


/* =====================================================================
   C3. Loans by status, and the overall default rate (status B or D)
   ===================================================================== */
-- Part 1: count, total and average amount per status
SELECT status,
       status_label,
       COUNT(*)    AS loans,
       SUM(amount) AS total_amount,
       AVG(amount) AS average_amount
FROM loan
GROUP BY status, status_label
ORDER BY status;

-- Part 2: overall default rate
SELECT CAST(ROUND(100.0 * AVG(is_default * 1.0), 1) AS DECIMAL(5,1)) AS default_rate_pct
FROM loan;
/* Finding:
   76 of 682 loans are in default (11.1% by count), but defaulted loans are much larger
   (avg 249,284 CZK for status D vs 91,641 for A), so they represent 15.1% of the total
   loan amount (15.6M of 103.3M CZK). Larger loans carry higher default risk. */
GO


/* =====================================================================
   C4. Default rate by region
   ===================================================================== */
SELECT d.region,
       COUNT(*)                                                        AS total_loans,
       SUM(CAST(l.is_default AS INT))                                  AS defaulted,
       CAST(ROUND(100.0 * AVG(l.is_default * 1.0), 1) AS DECIMAL(5,1)) AS default_rate_pct
FROM loan l
JOIN account a   ON l.account_id  = a.account_id
JOIN districts d ON a.district_id = d.district_id
GROUP BY d.region
ORDER BY default_rate_pct DESC;
/* Finding:
   West Bohemia has the highest default rate (15.8%), closely followed by North Moravia
   (15.4%) and South Bohemia (15.0%), all well above the bank average of 11.1%.
   North Moravia carries the largest absolute risk with 18 defaulted loans.
   North Bohemia looks safest (1.6%) but this is only 1 default out of 61 loans. */
GO


/* =====================================================================
   C5. Default rate by loan duration (months)
   ===================================================================== */
SELECT duration,
       COUNT(*)                                                       AS total_loans,
       SUM(CAST(is_default AS INT))                                   AS defaulted,
       CAST(ROUND(100.0 * AVG(is_default * 1.0), 1) AS DECIMAL(5,1))  AS default_rate_pct
FROM loan
GROUP BY duration
ORDER BY duration;
/* Finding:
   12-month loans have the lowest default rate (8.4%). From 24 months onwards the rate is
   almost flat (11.5%-12.3%), so longer duration alone is not a strong risk driver; the
   main jump happens between 1-year and 2-year loans. */
GO


/* =====================================================================
   C6. Do card holders default less?
   EXISTS keeps one row per loan even when an account has several
   owners/users or several cards (a plain JOIN would duplicate loans).
   ===================================================================== */
WITH loan_cards AS (
    SELECT l.loan_id,
           l.is_default,
           CASE WHEN EXISTS (SELECT 1
                             FROM disp d
                             JOIN cards c ON c.disp_id = d.disp_id
                             WHERE d.account_id = l.account_id)
                THEN 'Has card' ELSE 'No card' END AS card_status
    FROM loan l
)
SELECT card_status,
       COUNT(*)                                                       AS total_loans,
       SUM(CAST(is_default AS INT))                                   AS defaulted,
       CAST(ROUND(100.0 * AVG(is_default * 1.0), 1) AS DECIMAL(5,1))  AS default_rate_pct
FROM loan_cards
GROUP BY card_status;
/* Finding:
   Loans on accounts with a card default far less: 2.9% (5 of 170) vs 13.9% (71 of 512)
   for accounts without a card - almost 5x lower. This is a correlation, not a cause:
   cards are likely issued to more active, lower-risk clients, so card ownership can be
   used as one signal in credit scoring. */
GO


/* =====================================================================
   C7. Is there a link between district average salary and default?
   ===================================================================== */
WITH loan_salary AS (
    SELECT l.loan_id,
           l.is_default,
           d.avg_salary,
           CASE WHEN d.avg_salary < 9000  THEN 'Low'
                WHEN d.avg_salary < 10000 THEN 'Medium'
                ELSE 'High' END AS salary_band
    FROM loan l
    JOIN account a   ON l.account_id  = a.account_id
    JOIN districts d ON a.district_id = d.district_id
)
SELECT salary_band,
       AVG(avg_salary)                                                AS avg_salary,
       COUNT(*)                                                       AS total_loans,
       SUM(CAST(is_default AS INT))                                   AS defaulted,
       CAST(ROUND(100.0 * AVG(is_default * 1.0), 1) AS DECIMAL(5,1))  AS default_rate_pct
FROM loan_salary
GROUP BY salary_band
ORDER BY CASE salary_band WHEN 'Low' THEN 1 WHEN 'Medium' THEN 2 ELSE 3 END;
/* Finding:
   Districts with low average salaries (<9,000 CZK) have the highest default rate (12.3%)
   and hold over half of all loans (359 of 682). However, the link is weak: medium (9.6%)
   and high-salary districts (10.2%) are almost the same. District salary is an area-level
   average, not the client's own income, so it should be a secondary risk factor only. */
GO


/* =====================================================================
   C8. Monthly transaction volume in 1998 and month-over-month growth
   ===================================================================== */
WITH monthly AS (
    SELECT MONTH(trans_date) AS month_no,
           COUNT(*)          AS txns
    FROM trans
    WHERE YEAR(trans_date) = 1998
    GROUP BY MONTH(trans_date)
)
SELECT month_no,
       txns,
       LAG(txns) OVER (ORDER BY month_no) AS prev_month,
       CAST(ROUND((txns - LAG(txns) OVER (ORDER BY month_no)) * 100.0
                  / LAG(txns) OVER (ORDER BY month_no), 1) AS DECIMAL(6,1)) AS growth_pct
FROM monthly
ORDER BY month_no;
/* Finding:
   In 1998, January is an outlier with 42,940 transactions (almost double a normal month),
   likely due to start-of-year interest postings and fees. February's -44.1% is a return
   to normal, not a real decline. From February to November volume is stable at ~25,000
   per month, with a peak in June (+8.6%) and dips in July (-8.1%) and December (-7.1%). */
GO


/* =====================================================================
   C9. Last balance per account, then the top 3 accounts by balance per region
   ROW_NUMBER is used twice: once to find each account's latest transaction,
   once to rank accounts inside each region.
   ===================================================================== */
WITH last_txn AS (
    SELECT account_id,
           trans_date,
           balance,
           ROW_NUMBER() OVER (PARTITION BY account_id
                              ORDER BY trans_date DESC, trans_id DESC) AS rn
    FROM trans
),
ranked AS (
    SELECT d.region,
           lt.account_id,
           lt.trans_date AS last_txn_date,
           lt.balance    AS last_balance,
           ROW_NUMBER() OVER (PARTITION BY d.region
                              ORDER BY lt.balance DESC) AS rank_in_region
    FROM last_txn lt
    JOIN account a   ON lt.account_id = a.account_id
    JOIN districts d ON a.district_id = d.district_id
    WHERE lt.rn = 1
)
SELECT region, rank_in_region, account_id, last_txn_date, last_balance
FROM ranked
WHERE rank_in_region <= 3
ORDER BY region, rank_in_region;
/* Finding:
   The top 3 balances in every region are close to each other (~113K-127K CZK), so
   high-value clients are spread across all regions rather than concentrated in one.
   The highest balance in the bank is account 3255 in Prague (127,380 CZK). Most last
   transactions fall on 1998-12-31, the month-end interest posting date. */
GO


/* =====================================================================
   C10. Share of each transaction type in total activity
   ===================================================================== */
SELECT operation_en,
       COUNT(*) AS total_operations,
       CAST(ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS DECIMAL(5,1)) AS share_pct
FROM trans
GROUP BY operation_en
ORDER BY total_operations DESC;
/* Finding:
   Cash withdrawals dominate activity (41.2% of all transactions), followed by remittances
   to other banks (19.7%) and interest postings (17.3%). Card withdrawals are only 0.8%,
   so card usage is very low. Combined with C6 (card holders default ~5x less), this is an
   opportunity to grow card adoption. */
GO


/* =====================================================================
   C11. Do accounts that ever went into a negative balance default more?
   ===================================================================== */
WITH loan_overdraft AS (
    SELECT l.loan_id,
           l.is_default,
           CASE WHEN EXISTS (SELECT 1
                             FROM trans t
                             WHERE t.account_id = l.account_id
                               AND t.balance < 0)
                THEN 'Went negative' ELSE 'Never negative' END AS balance_status
    FROM loan l
)
SELECT balance_status,
       COUNT(*)                                                       AS total_loans,
       SUM(CAST(is_default AS INT))                                   AS defaulted,
       CAST(ROUND(100.0 * AVG(is_default * 1.0), 1) AS DECIMAL(5,1))  AS default_rate_pct
FROM loan_overdraft
GROUP BY balance_status;
/* Finding:
   All 76 loans whose account ever went below zero are in default (100%), while none of
   the 606 other loans defaulted (0%). This is very likely an effect, not a cause: when a
   borrower cannot pay, automatic loan instalments push the balance negative. So it should
   NOT be used as a predictive feature (data leakage), but it is a perfect early-warning
   trigger: any borrower account going negative should be flagged for immediate follow-up. */
GO


/* =====================================================================
   C12 (extra). Share of loans and default rate by borrower age group
   Each loan is linked to the account OWNER only, so it is counted once.
   ===================================================================== */
SELECT c.age_group,
       COUNT(*) AS loans,
       CAST(ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS DECIMAL(5,1)) AS share_of_loans_pct,
       CAST(ROUND(100.0 * AVG(l.is_default * 1.0), 1) AS DECIMAL(5,1))          AS default_rate_pct
FROM loan l
JOIN disp dp   ON dp.account_id = l.account_id AND dp.[type] = 'OWNER'
JOIN clients c ON c.client_id   = dp.client_id
GROUP BY c.age_group
ORDER BY CASE c.age_group WHEN 'Under 30' THEN 1 WHEN '30-49' THEN 2 ELSE 3 END;
/* Finding:
   30-49 year-olds take almost half of all loans (47.1%) while being 36% of clients.
   Clients aged 50+ are the largest group (40%) but take only 27.6% of loans.
   Default rates are similar across age groups (10.3%-12.8%; Under 30 = 11.0%),
   so age is not a strong risk factor. */
GO
