/* =====================================================================
   BerkaBank - 01_setup.sql
   Part A: create the database, load the 8 CSV files, add keys (SQL Server)

   Before running: put the 8 CSV files in C:\Berka\
   (change the path in every BULK INSERT if you use another folder).
   ===================================================================== */

CREATE DATABASE BerkaBank;
GO
USE BerkaBank;
GO

/* ---------------------------------------------------------------------
   A2. Create tables and load data
   --------------------------------------------------------------------- */

-- districts: A12 and A15 contain '?' for missing values, so load as text first
CREATE TABLE #districts_stg (
    A1 NVARCHAR(10), A2 NVARCHAR(50), A3 NVARCHAR(50), A4 NVARCHAR(20),
    A5 NVARCHAR(10), A6 NVARCHAR(10), A7 NVARCHAR(10), A8 NVARCHAR(10),
    A9 NVARCHAR(10), A10 NVARCHAR(10), A11 NVARCHAR(10), A12 NVARCHAR(10),
    A13 NVARCHAR(10), A14 NVARCHAR(10), A15 NVARCHAR(20), A16 NVARCHAR(20)
);
BULK INSERT #districts_stg FROM 'C:\Berka\district.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a');

CREATE TABLE districts (
    A1 TINYINT NOT NULL, A2 NVARCHAR(50) NOT NULL, A3 NVARCHAR(50) NOT NULL,
    A4 INT NOT NULL, A5 TINYINT NOT NULL, A6 TINYINT NOT NULL, A7 TINYINT NOT NULL,
    A8 TINYINT NOT NULL, A9 TINYINT NOT NULL, A10 FLOAT NOT NULL, A11 SMALLINT NOT NULL,
    A12 FLOAT NULL, A13 FLOAT NOT NULL, A14 TINYINT NOT NULL, A15 INT NULL, A16 INT NOT NULL
);
INSERT INTO districts
SELECT A1, A2, A3, A4, A5, A6, A7, A8, A9, A10, A11,
       TRY_CAST(A12 AS FLOAT),            -- '?' becomes NULL
       A13, A14,
       TRY_CAST(A15 AS INT),              -- '?' becomes NULL
       A16
FROM #districts_stg;
DROP TABLE #districts_stg;
GO

-- account: date is stored as YYMMDD (e.g. 930101), converted to DATE on load
CREATE TABLE #account_stg (account_id SMALLINT, district_id TINYINT, frequency NVARCHAR(50), [date] INT);
BULK INSERT #account_stg FROM 'C:\Berka\account.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a');

CREATE TABLE account (
    account_id  SMALLINT     NOT NULL,
    district_id TINYINT      NOT NULL,
    frequency   NVARCHAR(50) NOT NULL,
    [date]      DATE         NOT NULL
);
INSERT INTO account
SELECT account_id, district_id, frequency, CAST('19' + CAST([date] AS VARCHAR(6)) AS DATE)
FROM #account_stg;
DROP TABLE #account_stg;
GO

CREATE TABLE clients (
    client_id    SMALLINT NOT NULL,
    birth_number INT      NOT NULL,
    district_id  TINYINT  NOT NULL
);
BULK INSERT clients FROM 'C:\Berka\client.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a');
GO

CREATE TABLE disp (
    disp_id    SMALLINT     NOT NULL,
    client_id  SMALLINT     NOT NULL,
    account_id SMALLINT     NOT NULL,
    [type]     NVARCHAR(50) NOT NULL
);
BULK INSERT disp FROM 'C:\Berka\disp.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a');
GO

CREATE TABLE cards (
    card_id SMALLINT     NOT NULL,
    disp_id SMALLINT     NOT NULL,
    [type]  NVARCHAR(50) NOT NULL,
    issued  NVARCHAR(50) NOT NULL          -- e.g. '931107 00:00:00', converted in 02_cleaning
);
BULK INSERT cards FROM 'C:\Berka\card.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a');
GO

-- loan: date converted to DATE on load
CREATE TABLE #loan_stg (loan_id SMALLINT, account_id SMALLINT, [date] INT, amount INT,
                        duration TINYINT, payments FLOAT, status NVARCHAR(50));
BULK INSERT #loan_stg FROM 'C:\Berka\loan.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a');

CREATE TABLE loan (
    loan_id    SMALLINT     NOT NULL,
    account_id SMALLINT     NOT NULL,
    [date]     DATE         NOT NULL,
    amount     INT          NOT NULL,
    duration   TINYINT      NOT NULL,
    payments   FLOAT        NOT NULL,
    status     NVARCHAR(50) NOT NULL
);
INSERT INTO loan
SELECT loan_id, account_id, CAST('19' + CAST([date] AS VARCHAR(6)) AS DATE),
       amount, duration, payments, status
FROM #loan_stg;
DROP TABLE #loan_stg;
GO

-- 'order' is a reserved word in SQL, so the table is named orders
CREATE TABLE orders (
    order_id   INT          NOT NULL,
    account_id SMALLINT     NOT NULL,
    bank_to    NVARCHAR(50) NOT NULL,
    account_to INT          NOT NULL,
    amount     FLOAT        NOT NULL,
    k_symbol   NVARCHAR(50) NULL
);
BULK INSERT orders FROM 'C:\Berka\order.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a');
GO

-- trans: ~1 million rows; balance can be negative (overdrafts)
CREATE TABLE trans (
    trans_id   INT           NOT NULL,
    account_id SMALLINT      NOT NULL,
    [date]     INT           NOT NULL,     -- YYMMDD, converted in 02_cleaning
    [type]     NVARCHAR(20)  NOT NULL,
    operation  NVARCHAR(50)  NULL,
    amount     DECIMAL(12,2) NOT NULL,
    balance    DECIMAL(12,2) NOT NULL,
    k_symbol   NVARCHAR(50)  NULL,
    bank       NVARCHAR(10)  NULL,
    account    NVARCHAR(20)  NULL
);
BULK INSERT trans FROM 'C:\Berka\trans.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0d0a', TABLOCK);
GO

/* ---------------------------------------------------------------------
   A3. Primary keys and foreign keys
   --------------------------------------------------------------------- */
ALTER TABLE account   ADD CONSTRAINT PK_account   PRIMARY KEY (account_id);
ALTER TABLE clients   ADD CONSTRAINT PK_clients   PRIMARY KEY (client_id);
ALTER TABLE disp      ADD CONSTRAINT PK_disp      PRIMARY KEY (disp_id);
ALTER TABLE cards     ADD CONSTRAINT PK_cards     PRIMARY KEY (card_id);
ALTER TABLE loan      ADD CONSTRAINT PK_loan      PRIMARY KEY (loan_id);
ALTER TABLE orders    ADD CONSTRAINT PK_orders    PRIMARY KEY (order_id);
ALTER TABLE trans     ADD CONSTRAINT PK_trans     PRIMARY KEY (trans_id);
ALTER TABLE districts ADD CONSTRAINT PK_districts PRIMARY KEY (A1);
GO

ALTER TABLE account ADD CONSTRAINT FK_account_districts FOREIGN KEY (district_id) REFERENCES districts (A1);
ALTER TABLE clients ADD CONSTRAINT FK_clients_districts FOREIGN KEY (district_id) REFERENCES districts (A1);
ALTER TABLE disp    ADD CONSTRAINT FK_disp_clients      FOREIGN KEY (client_id)   REFERENCES clients (client_id);
ALTER TABLE disp    ADD CONSTRAINT FK_disp_account      FOREIGN KEY (account_id)  REFERENCES account (account_id);
ALTER TABLE cards   ADD CONSTRAINT FK_cards_disp        FOREIGN KEY (disp_id)     REFERENCES disp (disp_id);
ALTER TABLE loan    ADD CONSTRAINT FK_loan_account      FOREIGN KEY (account_id)  REFERENCES account (account_id);
ALTER TABLE orders  ADD CONSTRAINT FK_orders_account    FOREIGN KEY (account_id)  REFERENCES account (account_id);
ALTER TABLE trans   ADD CONSTRAINT FK_trans_account     FOREIGN KEY (account_id)  REFERENCES account (account_id);
GO

/* ---------------------------------------------------------------------
   A5. Row count per table
   Expected: account 4,500 | cards 892 | clients 5,369 | disp 5,369 |
             districts 77 | loan 682 | orders 6,471 | trans 1,056,320
   --------------------------------------------------------------------- */
SELECT 'account'   AS table_name, COUNT(*) AS row_count FROM account
UNION ALL SELECT 'cards',     COUNT(*) FROM cards
UNION ALL SELECT 'clients',   COUNT(*) FROM clients
UNION ALL SELECT 'disp',      COUNT(*) FROM disp
UNION ALL SELECT 'districts', COUNT(*) FROM districts
UNION ALL SELECT 'loan',      COUNT(*) FROM loan
UNION ALL SELECT 'orders',    COUNT(*) FROM orders
UNION ALL SELECT 'trans',     COUNT(*) FROM trans
ORDER BY row_count DESC;
