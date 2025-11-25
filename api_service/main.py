from fastapi import FastAPI, HTTPException
from google.cloud import storage
from prophet.serialize import model_from_json
import pandas as pd
import os
import json
import io
import logging

# --- Setup Logging ---
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- Configuration ---
PROJECT_ID = os.environ.get("GCP_PROJECT_ID")
MODEL_BUCKET = os.environ.get("MODEL_BUCKET")
MODEL_FILENAME = "model.json"

model = None

# --- Lifecycle ---
from contextlib import asynccontextmanager


@asynccontextmanager
async def lifespan(app: FastAPI):
    global model
    try:
        logger.info(f"Loading model gs://{MODEL_BUCKET}/{MODEL_FILENAME}...")
        storage_client = storage.Client(project=PROJECT_ID)
        bucket = storage_client.bucket(MODEL_BUCKET)
        blob = bucket.blob(MODEL_FILENAME)

        model_json_str = blob.download_as_text()
        model = model_from_json(json.loads(model_json_str))
        logger.info("Model loaded successfully.")

    except Exception as e:
        logger.error(f"FATAL: Model could not be loaded. {e}")
        model = None
    yield


app = FastAPI(lifespan=lifespan)

# --- Prediction Endpoint ---
@app.get("/predict")
async def predict(days: int = 7):
    if model is None:
        raise HTTPException(status_code=503, detail="Model not loaded.")

    try:
        # 1. Create future dates
        future_hours = days * 24
        future_df = model.make_future_dataframe(periods=future_hours, freq="h")

        # 2. Predict
        forecast_df = model.predict(future_df)

        # 3. Filter for future dates
        # FIX: Ensure both are timezone-naive for comparison
        now = pd.Timestamp.now().replace(tzinfo=None)
        forecast_df["ds"] = pd.to_datetime(forecast_df["ds"]).dt.tz_localize(None)

        # Log the range of dates the model knows about
        last_model_date = forecast_df["ds"].max()
        logger.info(f"Current Time: {now}")
        logger.info(f"Model Forecasts until: {last_model_date}")

        future_forecast = forecast_df[forecast_df["ds"] > now]

        if future_forecast.empty:
            logger.warning("Forecast is empty! The model might be trained on old data.")
            # Fallback: Return the last 24 hours of the forecast anyway so we see SOMETHING
            return (
                forecast_df.tail(24)[["ds", "yhat"]]
                .astype(str)
                .to_dict(orient="records")
            )

        # 4. Format result
        result = future_forecast[["ds", "yhat", "yhat_lower", "yhat_upper"]]
        return result.astype(str).to_dict(orient="records")

    except Exception as e:
        logger.error(f"Prediction error: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/")
def root():
    return {"status": "ok", "model_loaded": model is not None}
