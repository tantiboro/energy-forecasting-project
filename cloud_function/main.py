import functions_framework
import requests
import pandas as pd
import os
from datetime import datetime, timedelta, timezone
from google.cloud import bigquery
from google.cloud import secretmanager

# --- 1. Global Variables ---
PROJECT_ID = os.environ.get("GCP_PROJECT_ID")
TABLE_ID = os.environ.get("TABLE_ID")
SECRET_ID = os.environ.get("SECRET_ID")

def get_api_key():
    """Fetches the EIA API key from Google Secret Manager."""
    try:
        client = secretmanager.SecretManagerServiceClient()
        name = f"projects/{PROJECT_ID}/secrets/{SECRET_ID}/versions/latest"
        response = client.access_secret_version(request={"name": name})
        return response.payload.data.decode("UTF-8")
    except Exception as e:
        print(f"Error fetching secret: {e}")
        raise

def fetch_and_load_data(api_key):
    """Fetches data from EIA and loads it into BigQuery."""
    
    # --- DYNAMIC DATES ---
    # Get data for the last 7 days
    now = datetime.now(timezone.utc)
    start_date = (now - timedelta(days=7)).strftime("%Y-%m-%dT%H")
    end_date = now.strftime("%Y-%m-%dT%H")

    print(f"Fetching data from {start_date} to {end_date}...")

    # --- 2. Make the API Call (UPDATED FOR CISO) ---
    # Using the region-data endpoint as verified in your local script
    base_url = "https://api.eia.gov/v2/electricity/rto/region-data/data/"
    
    params = {
        "api_key": api_key,
        "frequency": "hourly",
        "data[0]": "value",
        "facets[respondent][]": "CISO",   # California ISO
        "facets[type][]": "D",            # Demand only
        "start": start_date,
        "end": end_date,
        "sort[0][column]": "period",
        "sort[0][direction]": "asc",
        "offset": 0,
        "length": 5000
    }
    
    print(f"Querying EIA API at: {base_url}...")
    response = requests.get(base_url, params=params)
    response.raise_for_status()
    print("API call successful.")

    # --- 3. Parse and Clean Data ---
    data = response.json()
    if not data.get("response", {}).get("data"):
        print("No data returned from API.")
        return
        
    df = pd.json_normalize(data['response']['data'])

    # Updated column mapping for CISO/region-data endpoint
    df.rename(columns={
        "period": "timestamp",
        "value": "demand_mwh",
        "value-units": "units",
        "respondent": "region_code",       # Maps to new BigQuery schema
        "respondent-name": "region_name"
    }, inplace=True)
    
    df['timestamp'] = pd.to_datetime(df['timestamp'])
    df['demand_mwh'] = pd.to_numeric(df['demand_mwh'], errors='coerce')
    
    # Select columns matching the new BigQuery schema
    final_df = df[[
        "timestamp",
        "demand_mwh",
        "units",
        "region_code",
        "region_name"
    ]]
    
    print(f"Successfully parsed {len(final_df)} rows.")

    # --- 4. Load Data into BigQuery ---
    client = bigquery.Client()
    job_config = bigquery.LoadJobConfig(write_disposition="WRITE_APPEND")
    
    print(f"Loading data into BigQuery table: {TABLE_ID}...")
    job = client.load_table_from_dataframe(final_df, TABLE_ID, job_config=job_config)
    job.result()
    print(f"Load job complete. Loaded {job.output_rows} rows.")

@functions_framework.http
def etl_entry_point(request):
    try:
        print("Fetching API key...")
        api_key = get_api_key()
        
        print("Fetching and loading data...")
        fetch_and_load_data(api_key)
        
        return "Data ingestion complete.", 200
        
    except Exception as e:
        print(f"Error in function execution: {e}")
        return f"Error: {e}", 500