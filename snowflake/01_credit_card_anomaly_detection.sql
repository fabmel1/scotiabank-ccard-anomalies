--Creating Infrastructure
CREATE WAREHOUSE IF NOT EXISTS SCOTIABANK_WH
  WITH WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 300
  AUTO_RESUME = TRUE;

CREATE DATABASE IF NOT EXISTS SCOTIABANK_DB;

--Setting work environment
USE WAREHOUSE SCOTIABANK_WH;
USE SCOTIABANK_DB;
USE SCHEMA PUBLIC;

--Creating Transactions Table from scratch (last 3 days)
CREATE OR REPLACE TABLE SCOTIABANK_TRANSACTIONS_ALBERTA AS
WITH time_series AS (
    SELECT 
        DATEADD('minute', (ROW_NUMBER() OVER (ORDER BY NULL) - 1) * 30, DATEADD('day', -3, CURRENT_TIMESTAMP())) AS transaction_timestamp
    FROM TABLE(GENERATOR(ROWCOUNT => 144))
),
expansion AS (
    SELECT 
        t.transaction_timestamp,        
    FROM time_series t
    CROSS JOIN (SELECT SEQ4() AS seq FROM TABLE(GENERATOR(ROWCOUNT => 10))) s
)
,
catalogs AS (
    SELECT 
        ARRAY_CONSTRUCT('SCOTIA-CA-001', 'SCOTIA-CA-002', 'SCOTIA-CA-003', 'SCOTIA-CA-004', 'SCOTIA-CA-005', 
                        'SCOTIA-CA-006', 'SCOTIA-CA-007', 'SCOTIA-CA-008', 'SCOTIA-CA-009', 'SCOTIA-CA-010') AS cards,
        ARRAY_CONSTRUCT('Calgary', 'Edmonton', 'Red Deer', 'Banff', 'Lethbridge') AS cities,
        ARRAY_CONSTRUCT('Supermarket', 'Gas Station', 'Restaurant', 'Electronics') AS merchants
)
SELECT 
    e.transaction_timestamp,
    c.cards[UNIFORM(0, 9, RANDOM())]::STRING AS card_id,
    CASE 
        -- Inject anomaly intended (5% probability) with high amounts (CAD $2500 - CAD $5000)
        WHEN UNIFORM(0.0, 1.0, RANDOM()) < 0.05 THEN ROUND(UNIFORM(2500.0, 5000.0, RANDOM()), 2)
        -- Normal amounts for everyday transactions (CAD $20 - CAD $200)
        ELSE ROUND(UNIFORM(20.0, 200.0, RANDOM()), 2)
    END AS transaction_amount,
    c.merchants[UNIFORM(0, 3, RANDOM())]::STRING AS merchant_category,
    c.cities[UNIFORM(0, 4, RANDOM())]::STRING AS city,
    FALSE as no_label
FROM expansion e
CROSS JOIN catalogs c;

SELECT * FROM SCOTIABANK_TRANSACTIONS_ALBERTA;