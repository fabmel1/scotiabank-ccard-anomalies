# Cloud Anomaly Detection: Snowflake vs. Databricks 

This repository is part of a comparative project designed to evaluate Machine Learning and Artificial Intelligence solutions from a **data engineering** perspective. The case study simulates the detection of unusual and potentially fraudulent credit card transactions for **Scotiabank in the province of Alberta, Canada**.

The primary objective is to answer a key question for data engineers: *Is the complexity of setting up external ML environments (like Databricks) worth it, or can advanced use cases be solved directly with Snowflake's native features?*

---

## 🏗️ Architecture of Approach 1: Snowflake ML

This module implements an end-to-end pipeline purely in SQL and managed functions inside Snowflake, avoiding external cluster management, Python dependencies, or container infrastructure.

```text
[ Synthetic Generator (SQL) ] 
       │
       ▼
[ Alberta Transactions Table ] 
       │
       ├─────────────────────────┐
       ▼                         ▼
[ Training Data ]          [ Streaming / Incoming Data ]
       │                         │
       ▼                         ▼
[ SNOWFLAKE.ML.ANOMALY_DETECTION ] ──► [ !DETECT_ANOMALIES ] ──► [ Prioritized Alerts (DISTANCE) ]
```

---

## 📂 Repository Structure

```text
.
├── snowflake/
│   ├── 01_generate_synthetic_data.sql    # Synthetic transaction generation via pure SQL
│   ├── 02_train_anomaly_detector.sql     # Native time-series anomaly model training
│   └── 03_detect_and_prioritize.sql      # Inference and anomaly ranking by severity
└── README.md
```

---

## 🚀 Deployment and Execution Guide in Snowflake

Copy and run the following code blocks sequentially in your Snowflake console (`Snowsight`).

### Step 1: Synthetic Data Generation
This script uses Snowflake's native generators (`GENERATOR`) to simulate a constant stream of transactions split by time intervals, cards, and merchants across Alberta cities, injecting a controlled percentage of high-amount anomalies.

```sql
USE WAREHOUSE COMPUTE_WH;
USE DATABASE SCOTIABANK_DB;
USE SCHEMA PUBLIC;

-- Create or replace the full table with simulated transactions
CREATE OR REPLACE TABLE scotiabank_transactions_alberta AS
WITH 
time_series AS (
    SELECT 
        DATEADD('minute', (ROW_NUMBER() OVER (ORDER BY NULL) - 1) * 30, DATEADD('day', -3, CURRENT_TIMESTAMP())) AS transaction_timestamp
    FROM TABLE(GENERATOR(ROWCOUNT => 144))
),
expansion AS (
    SELECT t.transaction_timestamp FROM time_series t CROSS JOIN (SELECT SEQ4() AS seq FROM TABLE(GENERATOR(ROWCOUNT => 10)))
),
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
        WHEN UNIFORM(0.0, 1.0, RANDOM()) < 0.05 THEN ROUND(UNIFORM(2500.0, 5000.0, RANDOM()), 2)
        ELSE ROUND(UNIFORM(20.0, 200.0, RANDOM()), 2)
    END AS transaction_amount,
    FALSE AS no_label, -- Boolean column required by the model signature
    c.merchants[UNIFORM(0, 3, RANDOM())]::STRING AS merchant_category,
    c.cities[UNIFORM(0, 4, RANDOM())]::STRING AS city
FROM expansion e
CROSS JOIN catalogs c;
```

### Step 2: Data Splitting (Training vs. Incoming)
To comply with Snowflake's temporal evaluation rule (evaluation data must be subsequent to the training data), we split the dataset:

```sql
-- 1. Historical data to train the model
CREATE OR REPLACE TABLE scotiabank_training_data AS
SELECT * FROM scotiabank_transactions_alberta
WHERE transaction_timestamp <= DATEADD('hour', -6, CURRENT_TIMESTAMP());

-- 2. New simulated movements (recent streaming) to hunt for anomalies
CREATE OR REPLACE TABLE scotiabank_incoming_transactions AS
SELECT * FROM scotiabank_transactions_alberta
WHERE transaction_timestamp > DATEADD('hour', -6, CURRENT_TIMESTAMP());
```

### Step 3: Native Model Training
A time-series model grouped by `card_id` is trained fully managed by Snowflake:

```sql
CREATE OR REPLACE SNOWFLAKE.ML.ANOMALY_DETECTION basic_model(
    INPUT_DATA => TABLE(scotiabank_training_data),
    TIMESTAMP_COLNAME => 'transaction_timestamp',
    TARGET_COLNAME => 'transaction_amount',
    SERIES_COLNAME => 'card_id',
    LABEL_COLNAME => 'no_label'
);
```

### Step 4: Inference and Severity Prioritization
We run detection on incoming data. Results are sorted from highest to lowest severity using the **`DISTANCE`** metric (standard deviations relative to the expected upper bound):

```sql
CREATE OR REPLACE TABLE detected_anomalies_snowflake AS
SELECT 
    * 
FROM 
    TABLE(basic_model!DETECT_ANOMALIES(
        INPUT_DATA => TABLE(scotiabank_incoming_transactions),
        TIMESTAMP_COLNAME => 'transaction_timestamp',
        TARGET_COLNAME => 'transaction_amount',
        SERIES_COLNAME => 'card_id'
    ));

-- Query anomalies sorted from most severe to least severe
SELECT 
    transaction_timestamp,
    card_id,
    transaction_amount,
    forecast,
    lower_bound,
    upper_bound,
    distance,
    percentile,
    is_anomaly
FROM 
    detected_anomalies_snowflake
WHERE 
    is_anomaly = TRUE
ORDER BY 
    ABS(distance) DESC;
```

---

## 📊 Key Metrics Dictionary

*   **`FORECAST`**: Central value predicted by the model based on card seasonality.
*   **`LOWER_BOUND` / `UPPER_BOUND`**: Confidence interval or expected normal band.
*   **`DISTANCE`**: Measures how far the actual value strayed from the predicted band. The higher it is, the more atypical and severe the financial movement.
*   **`PERCENTILE`**: Cumulative probability of the error within the distribution.

---

## ⚖️ Advantages of Snowflake in this Approach (Data Engineer Perspective)
1. **Zero Data Movement:** Data never leaves Snowflake's secure storage into external compute clusters.
2. **Minimal Learning Curve:** No need to master Python libraries (`scikit-learn`, `pandas`), `pip` dependency management, or Spark cluster lifecycles. Everything is resolved using standard SQL queries and exclamation mark (`!`) method calls.