# Cloud Anomaly Detection: Snowflake vs. Databricks

This repository contains a comparative data engineering project evaluating Machine Learning and AI solutions across two leading cloud data platforms: **Snowflake** and **Databricks**. 

The case study simulates the detection of unusual and potentially fraudulent credit card transactions for **Scotiabank in the province of Alberta, Canada**.

The primary objective is to answer a key architectural question for data engineers: *Is the complexity of setting up external ML environments (like Databricks) worth it, or can advanced use cases be solved efficiently with Snowflake's native features?*

---

## 🏗️ Comparative Architecture Overview

```text
                               ┌─────────────────────────────────┐
                               │ Synthetic Data Generator (SQL)  │
                               └────────────────┬────────────────┘
                                                │
                                                ▼
                               ┌─────────────────────────────────┐
                               │  Scotiabank Transactions Table  │
                               └────────┬───────────────┬────────┘
                                        │               │
                      ┌─────────────────┘               └─────────────────┐
                      ▼                                                   ▼
         [ APPROACH 1: SNOWFLAKE ]                            [ APPROACH 2: DATABRICKS ]
                      │                                                   │
         • Native SQL Data Split                              • PySpark Data Split
         • SNOWFLAKE.ML.ANOMALY_DETECTION                     • Delta Lake Tables
         • `!DETECT_ANOMALIES` (Time-series)                  • Python / Scikit-Learn (Isolation Forest)
         • Execution Time: ~50-60s                            • Execution Time: ~5s
                      │                                                   │
                      └─────────────────┬─────────────────┘
                                        │
                                        ▼
                         [ Prioritized Fraud Alerts ]
```

---

## 📂 Repository Structure

```text
.
├── snowflake/
│   ├── 01_generate_synthetic_data.sql    # Synthetic transaction generation via pure SQL
│   ├── 02_train_anomaly_detector.sql     # Native time-series anomaly model training
│   └── 03_detect_and_prioritize.sql      # Inference and anomaly ranking by severity
├── databricks/
│   ├── Anomaly detectrion Scotiabank.ipynb # All in one notebook
└── README.md
```

---

## Part 1: Snowflake Implementation (Native SQL AI)

In Snowflake, everything is handled natively inside the data warehouse using built-in machine learning functions and standard SQL queries.

### Step 1: Synthetic Data Generation
```sql
USE WAREHOUSE COMPUTE_WH;
USE DATABASE SCOTIABANK_DB;
USE SCHEMA PUBLIC;

CREATE OR REPLACE TABLE scotiabank_transactions_alberta AS
WITH 
time_series AS (
    SELECT DATEADD('minute', (ROW_NUMBER() OVER (ORDER BY NULL) - 1) * 30, DATEADD('day', -3, CURRENT_TIMESTAMP())) AS transaction_timestamp
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
    FALSE AS no_label,
    c.merchants[UNIFORM(0, 3, RANDOM())]::STRING AS merchant_category,
    c.cities[UNIFORM(0, 4, RANDOM())]::STRING AS city
FROM expansion e
CROSS JOIN catalogs c;
```

### Step 2: Training vs. Incoming Split & Model Training
```sql
CREATE OR REPLACE TABLE scotiabank_training_data AS
SELECT * FROM scotiabank_transactions_alberta
WHERE transaction_timestamp <= DATEADD('hour', -6, CURRENT_TIMESTAMP());

CREATE OR REPLACE TABLE scotiabank_incoming_transactions AS
SELECT * FROM scotiabank_transactions_alberta
WHERE transaction_timestamp > DATEADD('hour', -6, CURRENT_TIMESTAMP());

CREATE OR REPLACE SNOWFLAKE.ML.ANOMALY_DETECTION basic_model(
    INPUT_DATA => TABLE(scotiabank_training_data),
    TIMESTAMP_COLNAME => 'transaction_timestamp',
    TARGET_COLNAME => 'transaction_amount',
    SERIES_COLNAME => 'card_id',
    LABEL_COLNAME => 'no_label'
);
```

### Step 3: Inference and Prioritization
```sql
CREATE OR REPLACE TABLE detected_anomalies_snowflake AS
SELECT * FROM TABLE(basic_model!DETECT_ANOMALIES(
    INPUT_DATA => TABLE(scotiabank_incoming_transactions),
    TIMESTAMP_COLNAME => 'transaction_timestamp',
    TARGET_COLNAME => 'transaction_amount',
    SERIES_COLNAME => 'card_id'
));

SELECT transaction_timestamp, card_id, transaction_amount, distance, is_anomaly
FROM detected_anomalies_snowflake
WHERE is_anomaly = TRUE
ORDER BY ABS(distance) DESC;
```

---

## Part 2: Databricks Implementation (PySpark & Scikit-Learn)

Databricks decouples processing storage (Delta Lake) from compute, leveraging Python's `scikit-learn` library for high-speed anomaly detection via an **Isolation Forest** model.

### Step 1: Synthetic Data Generation (Spark SQL)
```sql
CREATE OR REPLACE TABLE scotiabank_transactions_alberta AS
WITH time_series AS (
    SELECT EXPLODE(sequence(current_timestamp() - INTERVAL 3 DAY, current_timestamp(), INTERVAL 30 MINUTE)) AS transaction_timestamp
),
expansion AS (
    SELECT t.transaction_timestamp FROM time_series t CROSS JOIN (SELECT EXPLODE(sequence(1, 10)) AS seq)
),
catalogs AS (
    SELECT 
        array('SCOTIA-CA-001', 'SCOTIA-CA-002', 'SCOTIA-CA-003', 'SCOTIA-CA-004', 'SCOTIA-CA-005', 
              'SCOTIA-CA-006', 'SCOTIA-CA-007', 'SCOTIA-CA-008', 'SCOTIA-CA-009', 'SCOTIA-CA-010') AS cards,
        array('Calgary', 'Edmonton', 'Red Deer', 'Banff', 'Lethbridge') AS cities,
        array('Supermarket', 'Gas Station', 'Restaurant', 'Electronics') AS merchants
)
SELECT 
    e.transaction_timestamp,
    c.cards[CAST(rand() * 9 AS INT)] AS card_id,
    CASE 
        WHEN rand() < 0.05 THEN ROUND(2500 + rand() * 2500, 2)
        ELSE ROUND(20 + rand() * 180, 2)
    END AS transaction_amount,
    c.merchants[CAST(rand() * 3 AS INT)] AS merchant_category,
    c.cities[CAST(rand() * 4 AS INT)] AS city
FROM expansion e
CROSS JOIN catalogs c;
```

### Step 2: Data Splitting (Spark SQL)
```sql
CREATE OR REPLACE TABLE scotiabank_training_data AS
SELECT * FROM scotiabank_transactions_alberta
WHERE transaction_timestamp <= (current_timestamp() - INTERVAL 6 HOUR);

CREATE OR REPLACE TABLE scotiabank_incoming_transactions AS
SELECT * FROM scotiabank_transactions_alberta
WHERE transaction_timestamp > (current_timestamp() - INTERVAL 6 HOUR);
```

### Step 3: Model Training & Inference (Python / Scikit-Learn)
```python
import pandas as pd
from sklearn.ensemble import IsolationForest

df_train = spark.read.table("scotiabank_training_data").toPandas()
df_incoming = spark.read.table("scotiabank_incoming_transactions").toPandas()

model = IsolationForest(contamination=0.05, random_state=42)
model.fit(df_train[["transaction_amount"]])

df_incoming["raw_prediction"] = model.predict(df_incoming[["transaction_amount"]])
df_incoming["is_anomaly"] = df_incoming["raw_prediction"] == -1
df_incoming["anomaly_score"] = model.decision_function(df_incoming[["transaction_amount"]])

detected_anomalies = df_incoming[df_incoming["is_anomaly"] == True]
spark.createDataFrame(detected_anomalies).write.mode("overwrite").saveAsTable("detected_anomalies_databricks")
```

### Step 4: SQL Query on Databricks Results
```sql
SELECT transaction_timestamp, card_id, transaction_amount, anomaly_score, is_anomaly
FROM detected_anomalies_databricks
ORDER BY anomaly_score ASC;
```

---

## ⚖️ Final Architectural Verdict

| Feature / Criteria | Snowflake ML | Databricks (PySpark + Scikit-Learn) |
| :--- | :--- | :--- |
| **Primary Language** | Pure SQL | Python / Spark SQL |
| **Data Movement** | Zero data movement (Runs in-storage) | Reads/Writes via Delta Lake storage |
| **Execution Speed** | Moderate (~50-60s for time-series forecasting) | Extremely Fast (~5s in-memory Pandas execution) |
| **Learning Curve** | Low (Standard SQL syntax & managed function calls) | Moderate (Requires Python & ML library knowledge) |
| **Ecosystem Flexibility** | Closed inside Snowflake ecosystem | Highly flexible (MLflow tracking, custom Python packages, massive scale Spark) |