import requests
import pandas as pd
import os
from google.cloud import bigquery  # <-- IMPORT NEW LIBRARY

# --- 1. Configuration ---
API_KEY = os.getenv("EIA_API_KEY")
if not API_KEY:
    raise EnvironmentError("EIA_API_KEY environment variable not set.")

# --- 2. Use the 'sub-ba' Endpoint ---
base_url = "https://api.eia.gov/v2/electricity/rto/region-sub-ba-data/data/"

# --- 3. Use a High-Volume Filter ---
params = {
    "api_key": API_KEY,
    "frequency": "hourly",
    "data[0]": "value",
    "facets[parent][]": "PJM",
    "facets[subba][]": "AEP",
    "start": "2024-10-01T00",
    "end": "2024-10-05T23",
    "sort[0][column]": "period",
    "sort[0][direction]": "asc",
    "offset": 0,
    "length": 5000,
}

# --- 4. Make the API Call ---
print(f"Querying EIA API at: {base_url}...")
response = requests.get(base_url, params=params)

try:
    response.raise_for_status()
    print("API call successful.")
except requests.exceptions.RequestException as e:
    print(f"API Request Failed: {e}")
    print("Full URL:", response.url)
    try:
        print("API Error:", response.json())
    except:
        pass
    raise SystemExit()

# --- 5. Parse and Clean the JSON Response ---
data = response.json()

if "response" not in data or "data" not in data["response"]:
    print("Error: 'response' or 'data' key not found in JSON.")
    raise SystemExit()

if not data["response"]["data"]:
    print("No data returned for this query.")
    raise SystemExit()

try:
    df = pd.json_normalize(data["response"]["data"])

    df.rename(
        columns={
            "period": "timestamp",
            "value": "demand_mwh",
            "value-units": "units",
            "parent-name": "region_name",
            "subba-name": "subba_name",  # <--- ADD THIS LINE
        },
        inplace=True,
    )

    # Convert 'timestamp' to datetime object
    df["timestamp"] = pd.to_datetime(df["timestamp"])

    # Convert 'demand_mwh' to a number
    df["demand_mwh"] = pd.to_numeric(df["demand_mwh"], errors="coerce")

    # Select *only* the columns that match our BigQuery schema
    final_df = df[
        [
            "timestamp",
            "demand_mwh",
            "units",
            "region_name",
            "subba_name",
            # "type-name"
        ]
    ]

    print("\nSuccessfully parsed data:")
    print(final_df.head())
    print(f"\nData types:\n{final_df.dtypes}")

except Exception as e:
    print(f"An error occurred during data processing: {e}")
    raise SystemExit()

# --- 6. Load Data into BigQuery ---
try:
    # Set the destination table ID
    # PROJECT_ID.DATASET_ID.TABLE_ID
    table_id = "energy-forecasting-project.energy_forecasting.hourly_demand"  # <-- UPDATE YOUR PROJECT ID IF DIFFERENT

    # Create a BigQuery client
    client = bigquery.Client()

    # Configure the load job
    job_config = bigquery.LoadJobConfig(
        # We are appending data, not overwriting the table
        write_disposition="WRITE_APPEND",
    )

    print(f"\nLoading {len(final_df)} rows into BigQuery table: {table_id}...")

    # Start the load job
    job = client.load_table_from_dataframe(final_df, table_id, job_config=job_config)

    # Wait for the job to complete
    job.result()

    print("Load job complete.")
    print(f"Loaded {job.output_rows} rows.")

except Exception as e:
    print(f"\nFailed to load data into BigQuery: {e}")
    # Print more detailed errors if available
    if hasattr(e, "errors"):
        print("Detailed errors:")
        for err in e.errors:
            print(f"- {err['message']}")
