/* =====================================================================
   BerkaBank - 02_cleaning.sql
   Part B: data cleaning & enrichment (SQL Server)
   Run AFTER 01_setup.sql. Each section adds new columns and keeps the
   original columns untouched, so every step can be checked or redone.
   ===================================================================== */

USE BerkaBank;
GO

/* ---------------------------------------------------------------------
   B1. Convert dates stored as numbers / text into DATE
   account.date and loan.date were already imported as DATE.
   trans.date  -> INT  (e.g. 930101)
   cards.issued -> TEXT (e.g. '931107 00:00:00')
   --------------------------------------------------------------------- */
ALTER TABLE trans ADD trans_date DATE;
ALTER TABLE cards ADD issued_date DATE;
GO

UPDATE trans SET trans_date  = CAST('19' + CAST([date] AS VARCHAR(6)) AS DATE);
UPDATE cards SET issued_date = CAST('19' + LEFT(issued, 6) AS DATE);
GO

-- Check: no row should fail to convert (expected 0 and 0)
SELECT COUNT(*) AS trans_not_converted FROM trans WHERE trans_date  IS NULL;
SELECT COUNT(*) AS cards_not_converted FROM cards WHERE issued_date IS NULL;
GO

/* ---------------------------------------------------------------------
   B2. Gender, birth date, age and age group from birth_number
   birth_number = YYMMDD for men, YY(MM+50)DD for women.
   --------------------------------------------------------------------- */
ALTER TABLE clients ADD gender     CHAR(1);
ALTER TABLE clients ADD birth_date DATE;
ALTER TABLE clients ADD age        INT;
ALTER TABLE clients ADD age_group  VARCHAR(10);
GO

UPDATE clients
SET gender = CASE WHEN birth_number / 100 % 100 > 12 THEN 'F' ELSE 'M' END;

UPDATE clients
SET birth_date = DATEFROMPARTS(
        1900 + birth_number / 10000,                                   -- year
        CASE WHEN gender = 'F' THEN birth_number / 100 % 100 - 50
             ELSE birth_number / 100 % 100 END,                        -- month
        birth_number % 100                                             -- day
    );

-- Age at the end of the dataset period (31 Dec 1998)
UPDATE clients SET age = DATEDIFF(YEAR, birth_date, '1998-12-31');

UPDATE clients
SET age_group = CASE WHEN age < 30 THEN 'Under 30'
                     WHEN age < 50 THEN '30-49'
                     ELSE '50+' END;
GO

-- Check: F 2,645 / M 2,724 ; Under 30 1,282 / 30-49 1,924 / 50+ 2,163
SELECT gender,    COUNT(*) AS clients FROM clients GROUP BY gender;
SELECT age_group, COUNT(*) AS clients FROM clients GROUP BY age_group;
GO

/* ---------------------------------------------------------------------
   B3. Translate Czech codes into English
   Notes found while profiling the data:
   - trans.type has an undocumented value 'VYBER' (16,666 rows) = withdrawal
   - trans.operation is NULL for interest postings (183,114 rows)
   - k_symbol has two kinds of "empty": NULL and a single space ' '
   --------------------------------------------------------------------- */
ALTER TABLE account ADD frequency_en VARCHAR(30);
ALTER TABLE trans   ADD type_en      VARCHAR(20);
ALTER TABLE trans   ADD operation_en VARCHAR(30);
ALTER TABLE trans   ADD k_symbol_en  VARCHAR(30);
ALTER TABLE orders  ADD k_symbol_en  VARCHAR(30);
GO

UPDATE account SET frequency_en =
    CASE WHEN frequency = 'POPLATEK MESICNE'   THEN 'Monthly'
         WHEN frequency = 'POPLATEK TYDNE'     THEN 'Weekly'
         WHEN frequency = 'POPLATEK PO OBRATU' THEN 'After Transaction'
    END;

UPDATE trans SET type_en =
    CASE WHEN [type] = 'PRIJEM'           THEN 'Credit'
         WHEN [type] IN ('VYDAJ', 'VYBER') THEN 'Withdrawal'
    END;

UPDATE trans SET operation_en =
    CASE WHEN operation = 'VKLAD'          THEN 'Cash Deposit'
         WHEN operation = 'VYBER'          THEN 'Cash Withdrawal'
         WHEN operation = 'VYBER KARTOU'   THEN 'Card Withdrawal'
         WHEN operation = 'PREVOD Z UCTU'  THEN 'Collection from Another Bank'
         WHEN operation = 'PREVOD NA UCET' THEN 'Remittance to Another Bank'
         WHEN operation IS NULL            THEN 'Interest'
    END;

UPDATE trans SET k_symbol_en =
    CASE WHEN k_symbol = 'POJISTNE'    THEN 'Insurance'
         WHEN k_symbol = 'SIPO'        THEN 'Household'
         WHEN k_symbol = 'SLUZBY'      THEN 'Statement Fee'
         WHEN k_symbol = 'UROK'        THEN 'Interest Credited'
         WHEN k_symbol = 'SANKC. UROK' THEN 'Overdraft Penalty'
         WHEN k_symbol = 'DUCHOD'      THEN 'Pension'
         WHEN k_symbol = 'UVER'        THEN 'Loan Payment'
         WHEN k_symbol IS NULL OR LTRIM(RTRIM(k_symbol)) = '' THEN 'Other'
    END;

UPDATE orders SET k_symbol_en =
    CASE WHEN k_symbol = 'UVER'     THEN 'Loan Payment'
         WHEN k_symbol = 'SIPO'     THEN 'Household'
         WHEN k_symbol = 'LEASING'  THEN 'Leasing'
         WHEN k_symbol = 'POJISTNE' THEN 'Insurance'
         WHEN k_symbol IS NULL OR LTRIM(RTRIM(k_symbol)) = '' THEN 'Other'
    END;
GO

-- Check: every code has a translation (no NULL in the *_en columns)
SELECT frequency, frequency_en, COUNT(*) AS accounts FROM account GROUP BY frequency, frequency_en;
SELECT [type],    type_en,      COUNT(*) AS txns     FROM trans   GROUP BY [type], type_en;
SELECT operation, operation_en, COUNT(*) AS txns     FROM trans   GROUP BY operation, operation_en;
SELECT k_symbol,  k_symbol_en,  COUNT(*) AS txns     FROM trans   GROUP BY k_symbol, k_symbol_en;
SELECT k_symbol,  k_symbol_en,  COUNT(*) AS orders_count FROM orders GROUP BY k_symbol, k_symbol_en;
GO

/* ---------------------------------------------------------------------
   B4. Loan status label and default flag
   A = finished OK, B = finished not paid, C = running OK, D = running in debt
   --------------------------------------------------------------------- */
ALTER TABLE loan ADD status_label VARCHAR(25);
ALTER TABLE loan ADD is_default   BIT;
GO

UPDATE loan SET status_label =
    CASE WHEN status = 'A' THEN 'Finished - OK'
         WHEN status = 'B' THEN 'Finished - Not Paid'
         WHEN status = 'C' THEN 'Running - OK'
         WHEN status = 'D' THEN 'Running - In Debt'
    END;

UPDATE loan SET is_default = CASE WHEN status IN ('B', 'D') THEN 1 ELSE 0 END;
GO

-- Check: A 203 / B 31 / C 403 / D 45  (76 defaults)
SELECT status, status_label, is_default, COUNT(*) AS loans
FROM loan
GROUP BY status, status_label, is_default
ORDER BY status;
GO

/* ---------------------------------------------------------------------
   B5. Give the districts columns meaningful names
   Missing values ('?') in A12 / A15 were imported as NULL (1 row each).
   --------------------------------------------------------------------- */
EXEC sp_rename 'districts.A1',  'district_id',            'COLUMN';
EXEC sp_rename 'districts.A2',  'district_name',          'COLUMN';
EXEC sp_rename 'districts.A3',  'region',                 'COLUMN';
EXEC sp_rename 'districts.A4',  'inhabitants',            'COLUMN';
EXEC sp_rename 'districts.A5',  'munic_under_500',        'COLUMN';
EXEC sp_rename 'districts.A6',  'munic_500_1999',         'COLUMN';
EXEC sp_rename 'districts.A7',  'munic_2000_9999',        'COLUMN';
EXEC sp_rename 'districts.A8',  'munic_over_10000',       'COLUMN';
EXEC sp_rename 'districts.A9',  'num_cities',             'COLUMN';
EXEC sp_rename 'districts.A10', 'urban_ratio',            'COLUMN';
EXEC sp_rename 'districts.A11', 'avg_salary',             'COLUMN';
EXEC sp_rename 'districts.A12', 'unemployment_95',        'COLUMN';
EXEC sp_rename 'districts.A13', 'unemployment_96',        'COLUMN';
EXEC sp_rename 'districts.A14', 'entrepreneurs_per_1000', 'COLUMN';
EXEC sp_rename 'districts.A15', 'crimes_95',              'COLUMN';
EXEC sp_rename 'districts.A16', 'crimes_96',              'COLUMN';
GO

-- float -> exact decimal so values show as 46.7 instead of 46.7000007629395
ALTER TABLE districts ALTER COLUMN urban_ratio DECIMAL(5,1);
GO

SELECT TOP 5 * FROM districts;
