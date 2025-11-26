⚡ Serverless Real-Time Energy Forecasting Platform

📖 Overview

This project is an end-to-end, fully automated MLOps platform that forecasts real-time energy demand for the PJM Interconnection (AEP Region).

Unlike static notebooks, this is a living system. It runs entirely on serverless infrastructure, ingests fresh data daily, retrains the machine learning model weekly to prevent drift, and serves predictions via a live API and Dashboard.

🚀 Live Dashboard: https://energy-dashboard-zwuubqodya-uc.a.run.app

🏗️ Architecture

The system is built 100% on Google Cloud Platform (GCP) using Terraform for Infrastructure as Code (IaC).

Data Pipeline (ETL)

Source: US Energy Information Administration (EIA) API.

Ingestion: A Python Cloud Function triggers daily via Cloud Scheduler.

Storage: Data is cleaned and loaded into a partitioned BigQuery table.

Machine Learning (MLOps)

Model: Facebook Prophet (Time-series forecasting).

Training: A second Cloud Function triggers weekly. It fetches the latest historical data from BigQuery, retrains the model, and serializes it to JSON.

Artifact Store: The trained model (model.json) is stored in Google Cloud Storage (GCS).

Serving & Visualization

API: A FastAPI microservice running on Cloud Run. It loads the latest model from GCS on startup and serves sub-second forecasts.

Dashboard: An interactive Streamlit app running on Cloud Run, visualizing the forecast with Plotly.

🛠️ Tech Stack

Infrastructure: Terraform, Docker, GitHub Actions (CI/CD)

Cloud: Google Cloud Platform (Cloud Run, Functions, Scheduler, BigQuery, GCS, Secret Manager)

Backend: Python 3.12, FastAPI, Pandas

ML: Prophet, Joblib

Frontend: Streamlit, Plotly

🔧 How to Run Locally

Clone the repository:

git clone [https://github.com/YOUR_USERNAME/serverless-energy-forecasting.git](https://github.com/YOUR_USERNAME/serverless-energy-forecasting.git)
cd serverless-energy-forecasting


Set up Environment:

# Create virtual environment
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# Install dependencies
pip install -r dashboard/requirements.txt


Run the Dashboard:

# You need to set the API URL environment variable first
export API_URL="[https://energy-forecasting-api-zwuubqodya-uc.a.run.app](https://energy-forecasting-api-zwuubqodya-uc.a.run.app)"
streamlit run dashboard/app.py


☁️ Deployment (CI/CD)

This project uses GitHub Actions for continuous deployment.

Push to Main: Any commit to the main branch triggers the pipeline.

Build: The pipeline rebuilds the Docker images for the API and Dashboard.

Push: Images are pushed to Google Artifact Registry.

Deploy: Terraform automatically applies infrastructure changes and updates the Cloud Run revisions.

🧠 Engineering Challenges ("War Stories")

Building this platform involved solving several complex engineering hurdles:

Binary Incompatibility: The API initially crashed with 503 errors because the model trained in Colab (Python 3.12) was pickled using a protocol incompatible with the older Cloud Run container.

Solution: Refactored the pipeline to serialize models to JSON instead of Pickle, making the artifacts version-agnostic.

The "Ghost App": The Streamlit dashboard loaded but showed a blank screen due to WebSocket 403 errors caused by the Cloud Run load balancer.

Solution: Implemented a "Golden Stack" configuration, forcing Streamlit to disable CORS/XSRF protection via Environment Variables in the Dockerfile.

Terraform State Locks: Encountered a "Deletion Protection" deadlock when updating the BigQuery schema.

Solution: Wrote a custom Python script to hit the GCP API directly and disable protection, allowing Terraform to destroy and recreate the resource with the correct schema, then refilled the data via the ETL pipeline.

🔮 Future Improvements

Weather Integration: Integrate Open-Meteo API to add temperature as a regressor to the Prophet model.

Monitoring: Add Cloud Monitoring alerts for pipeline failures.

Author

Tantiboro
https://linkedin.com/in/tanti-ouattara | https://github.com/tantiboro/tantiboro.github.io
