--Setting work environment

USE WAREHOUSE SCOTIABANK_WH;
USE SCOTIABANK_DB;
USE SCHEMA PUBLIC;

--Creating training and incoming transaction tables
CREATE OR REPLACE TABLE scotiabank_training_data AS
SELECT * FROM scotiabank_transactions_alberta
WHERE transaction_timestamp <= DATEADD('hour', -6, CURRENT_TIMESTAMP());

CREATE OR REPLACE TABLE scotiabank_incoming_transactions AS
SELECT * FROM scotiabank_transactions_alberta
WHERE transaction_timestamp > DATEADD('hour', -6, CURRENT_TIMESTAMP());


--Creating the anomaly detection model
CREATE OR REPLACE SNOWFLAKE.ML.ANOMALY_DETECTION basic_model(
    INPUT_DATA => TABLE(scotiabank_training_data),
    TIMESTAMP_COLNAME => 'transaction_timestamp',
    TARGET_COLNAME => 'transaction_amount',
    SERIES_COLNAME => 'card_id',
    LABEL_COLNAME => 'no_label'
);

--Detecting anomalies in incoming transactions
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

--Filtering detected anomalies
SELECT 
    *
FROM 
    detected_anomalies_snowflake
WHERE IS_ANOMALY = TRUE    
ORDER BY ABS(DISTANCE)
;