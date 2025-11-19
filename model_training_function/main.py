import functions_framework
import pandas as pd
import os
import joblib
from google.cloud import bigquery
from google.cloud import storage
from prophet import Prophet

# --- 1. Global Variables ---
# These will be set by Terraform
PROJECT_ID = os.environ.get("GCP_PROJECT_ID")
TABLE_ID = os.environ.get("TABLE_ID")
MODEL_BUCKET = os.environ.get("MODEL_BUCKET")
MODEL_FILENAME = "model.pkl"


def query_data():
    """Queries all data from the BigQuery warehouse."""
    print("Querying data from BigQuery...")
    client = bigquery.Client(project=PROJECT_ID)
    sql = f"""
    SELECT
        timestamp,
        demand_mwh
    FROM
        `{TABLE_ID}`
    ORDER BY
        timestamp ASC
    """
    df = client.query(sql).to_dataframe()
    print(f"Successfully loaded {len(df)} rows.")
    return df


def train_model(df):
    """Trains the Prophet model on the data."""
    print("Training the model...")

    # 1. Prepare the DataFrame for Prophet
    df_prophet = df.rename(columns={"timestamp": "ds", "demand_mwh": "y"})

    # 2. Remove timezone (Prophet requires this)
    df_prophet["ds"] = df_prophet["ds"].dt.tz_localize(None)

    # 3. Initialize and train
    model = Prophet(daily_seasonality=True, weekly_seasonality=True)
    model.fit(df_prophet)

    print("Model training complete.")
    return model


def save_model_to_gcs(model):
    """Saves the trained model to a GCS bucket."""

    # 1. Save model to a temporary local file
    local_path = f"/tmp/{MODEL_FILENAME}"
    joblib.dump(model, local_path)

    # 2. Upload the local file to GCS
    print(f"Uploading model to GCS bucket: {MODEL_BUCKET}...")
    storage_client = storage.Client()
    bucket = storage_client.bucket(MODEL_BUCKET)
    blob = bucket.blob(MODEL_FILENAME)

    blob.upload_from_filename(local_path)
    print(f"Model successfully uploaded to gs://{MODEL_BUCKET}/{MODEL_FILENAME}")


# --- 5. Main Function Entry Point ---
@functions_framework.http
def train_model_entry_point(request):
    """
    HTTP-triggered Cloud Function for model training.
    """
    try:
        df = query_data()
        model = train_model(df)
        save_model_to_gcs(model)

        return "Model training and saving complete.", 200

    except Exception as e:
        print(f"Error in function execution: {e}")
        return f"Error: {e}", 500
