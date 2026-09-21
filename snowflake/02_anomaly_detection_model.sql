-- 1. Set up the environment
USE WAREHOUSE SCOTIABANK_WH;
USE SCOTIABANK_DB;
USE SCHEMA PUBLIC;

-- 2. Create the anomaly detection model
CREATE OR REPLACE SNOWFLAKE.ML.ANOMALY_DETECTION basic_model(
  INPUT_DATA => TABLE(SCOTIABANK_TRANSACTIONS_ALBERTA),
  TIMESTAMP_COLNAME => 'transaction_timestamp',
  TARGET_COLNAME => 'transaction_amount',
  SERIES_COLNAME => 'card_id',
  LABEL_COLNAME => 'no_label');

-- 3. Detect anomalies in real-time on new batches of transactions
CREATE OR REPLACE TABLE detected_anomalies_snowflake AS
SELECT 
    * 
FROM 
    TABLE(basic_model!DETECT_ANOMALIES(
        INPUT_DATA => TABLE(SCOTIABANK_TRANSACTIONS_ALBERTA),
        TIMESTAMP_COLNAME => 'transaction_timestamp',
        TARGET_COLNAME => 'transaction_amount',
        SERIES_COLNAME => 'card_id'
    ));

-- 3. Consultar las alertas de fraude detectadas por el modelo nativo
SELECT 
    transaction_timestamp,
    card_id,
    transaction_amount,
    is_anomaly,
    anomaly_score,
    upper_bound,
    lower_bound
FROM 
    detected_anomalies_snowflake
WHERE 
    is_anomaly = TRUE
ORDER BY 
    anomaly_score DESC;