# Use Python 3.11 (Golden image for Streamlit 1.32)
FROM python:3.11-slim

WORKDIR /app

# 1. Install Golden Stack dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 2. Copy app code
COPY . .

# 3. CONFIGURE VIA ENVIRONMENT VARIABLES (The Fix)
# This overrides all config files and defaults.
ENV STREAMLIT_SERVER_PORT=8080
ENV STREAMLIT_SERVER_ADDRESS=0.0.0.0
ENV STREAMLIT_SERVER_HEADLESS=true

# Disable all security checks that break on Cloud Run
ENV STREAMLIT_SERVER_ENABLE_CORS=false
ENV STREAMLIT_SERVER_ENABLE_XSRF_PROTECTION=false
ENV STREAMLIT_SERVER_ENABLE_WEBSOCKET_COMPRESSION=false

# Disable stats to clean up logs
ENV STREAMLIT_BROWSER_GATHER_USAGE_STATS=false

EXPOSE 8080

# 4. Simple Execution
CMD ["streamlit", "run", "app.py"]
