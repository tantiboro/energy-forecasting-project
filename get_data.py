import requests
import pandas as pd
import os
from google.cloud import bigquery

# --- 1. Configuration ---
API_KEY = os.getenv("EIA_API_KEY")
if not API_KEY:
    raise EnvironmentError("EIA_API_KEY environment variable not set.")

# --- 2. USE THE CORRECT, ACTIVE ENDPOINT ---
base_url = "https://api.eia.gov/v2/electricity/rto/region-data/data/"

# --- 3. Query Parameters (VALID FOR 2024–2025) ---
params = {
    "api_key": API_KEY,
    "frequency": "hourly",
    "data[0]": "value",
    "facets[respondent][]": "CISO",  # <--- FIX: Use 'respondent' instead of 'region'
    "facets[type][]": "D",           # <--- FIX: Filter for 'D' (Demand) only
    "start": "2025-01-01T00",
    "end": "2025-01-05T23",
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
    print("API error details:", response.text)
    raise SystemExit()

# --- 5. Parse the JSON ---
data = response.json()

if "response" not in data or "data" not in data["response"]:
    print("Error: response/data missing in JSON")
    raise SystemExit()

rows = data["response"]["data"]
if not rows:
    print("No data returned for this query.")
    raise SystemExit()

df = pd.json_normalize(rows)

# --- 6. Standardize columns ---
# The API returns 'respondent' and 'respondent-name' now
df.rename(
    columns={
        "period": "timestamp",
        "value": "demand_mwh",
        "value-units": "units",
        "respondent": "region_code",       # <--- FIX: Map 'respondent' to region_code
        "respondent-name": "region_name",  # <--- FIX: Map 'respondent-name'
    },
    inplace=True,
)

df["timestamp"] = pd.to_datetime(df["timestamp"])
df["demand_mwh"] = pd.to_numeric(df["demand_mwh"], errors="coerce")

# --- 7. Build Final DataFrame ---
final_df = df[["timestamp", "demand_mwh", "units", "region_code", "region_name"]]

print("\nParsed data:")
print(final_df.head())
print(final_df.dtypes)

# --- 8. Load into BigQuery ---
try:
    # Ensure this matches your actual Project ID and Dataset
    table_id = "energy-forecasting-project.energy_forecasting.hourly_demand"

    client = bigquery.Client()

    job_config = bigquery.LoadJobConfig(write_disposition="WRITE_APPEND")

    print(f"\nLoading {len(final_df)} rows into BigQuery table: {table_id}...")

    job = client.load_table_from_dataframe(final_df, table_id, job_config=job_config)
    job.result()

    print("Load job complete.")
    print(f"Loaded {job.output_rows} rows.")

except Exception as e:
    print("\nFailed to load into BigQuery:", e)
