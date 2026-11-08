/* =====================================================================
   BerkaBank - 04_views.sql
   Part D: reporting views for Power BI (SQL Server)
   Run AFTER 01_setup.sql and 02_cleaning.sql
   CREATE OR ALTER lets this file be run again without errors.
   ===================================================================== */

USE BerkaBank;
GO

/* ---------------------------------------------------------------------
   D1. vw_loan_summary - one row per loan with status, region and card flag
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW vw_loan_summary AS
SELECT l.loan_id,
       l.account_id,
       l.[date] AS loan_date,
       l.amount,
       l.duration,
       l.payments,
       l.status,
       l.status_label,
       l.is_default,
       d.district_name,
       d.region,
       d.avg_salary,
       CASE WHEN EXISTS (SELECT 1
                         FROM disp di
                         JOIN cards c ON c.disp_id = di.disp_id
                         WHERE di.account_id = l.account_id)
            THEN 'Has card' ELSE 'No card' END AS card_status
FROM loan l
JOIN account a   ON l.account_id  = a.account_id
JOIN districts d ON a.district_id = d.district_id;
GO

/* ---------------------------------------------------------------------
   D2. vw_monthly_transactions - transactions per month and type
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW vw_monthly_transactions AS
SELECT DATEFROMPARTS(YEAR(trans_date), MONTH(trans_date), 1) AS month_start,
       type_en,
       COUNT(*)    AS txn_count,
       SUM(amount) AS total_amount
FROM trans
GROUP BY DATEFROMPARTS(YEAR(trans_date), MONTH(trans_date), 1), type_en;
GO

/* ---------------------------------------------------------------------
   D3. vw_client_profile - one row per client
   Subqueries / EXISTS are used instead of joins to disp, loan and cards
   so that a client never appears twice.
   --------------------------------------------------------------------- */
CREATE OR ALTER VIEW vw_client_profile AS
SELECT c.client_id,
       c.gender,
       c.birth_date,
       c.age,
       c.age_group,
       d.district_name,
       d.region,
       (SELECT COUNT(*) FROM disp dp
        WHERE dp.client_id = c.client_id) AS num_accounts,
       CASE WHEN EXISTS (SELECT 1 FROM disp dp
                         JOIN loan l ON l.account_id = dp.account_id
                         WHERE dp.client_id = c.client_id)
            THEN 1 ELSE 0 END AS has_loan,
       CASE WHEN EXISTS (SELECT 1 FROM disp dp
                         JOIN cards cr ON dp.disp_id = cr.disp_id
                         WHERE dp.client_id = c.client_id)
            THEN 1 ELSE 0 END AS has_card
FROM clients c
JOIN districts d ON d.district_id = c.district_id;
GO

/* ---------------------------------------------------------------------
   Checks (expected: 682 | ~144 | 5,369 clients, 827 with a loan, 892 with a card)
   --------------------------------------------------------------------- */
SELECT COUNT(*) AS loans FROM vw_loan_summary;
SELECT COUNT(*) AS month_type_rows FROM vw_monthly_transactions;
SELECT COUNT(*)      AS clients,
       SUM(has_loan) AS clients_with_loan,
       SUM(has_card) AS clients_with_card
FROM vw_client_profile;
