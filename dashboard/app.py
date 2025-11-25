import streamlit as st
import requests
import pandas as pd
import plotly.graph_objects as go
import os

# --- Configuration ---
# We will set this via Terraform, but this is a default
API_URL = os.environ.get("API_URL", "YOUR_API_URL_HERE")

st.set_page_config(page_title="Energy Forecaster", layout="wide")

# --- Header ---
st.title("⚡ Serverless Energy Forecasting (v3)")
st.markdown(
    """
This dashboard connects to a **Cloud Run** API serving a **Prophet** model.
The model is trained on **PJM/AEP** energy demand data stored in **BigQuery**.
"""
)

# --- Sidebar ---
st.sidebar.header("Forecast Settings")
days = st.sidebar.slider("Days to Forecast", min_value=1, max_value=30, value=7)

if st.sidebar.button("Generate Forecast"):
    with st.spinner("Fetching predictions from Cloud Run API..."):
        try:
            # Call the API
            response = requests.get(f"{API_URL}/predict", params={"days": days})
            response.raise_for_status()
            data = response.json()

            if not data:
                st.error("API returned empty data.")
            else:
                # Convert to DataFrame
                df = pd.DataFrame(data)
                df["ds"] = pd.to_datetime(df["ds"])

                # --- FIX 1: Safer Number Conversion ---
                # We iterate through columns that ACTUALLY EXIST in the dataframe
                # This prevents KeyErrors if yhat_lower is missing
                numeric_cols = ["yhat", "yhat_lower", "yhat_upper"]
                for col in numeric_cols:
                    if col in df.columns:
                        df[col] = pd.to_numeric(df[col], errors="coerce")
                # --------------------------------------

                # --- Metrics ---
                latest_pred = df.iloc[-1]["yhat"]
                avg_pred = df["yhat"].mean()

                col1, col2 = st.columns(2)
                col1.metric("Final Forecasted Demand", f"{latest_pred:,.0f} MW")
                col2.metric("Average Demand", f"{avg_pred:,.0f} MW")

                # --- Plot ---
                fig = go.Figure()

                # Main forecast line
                fig.add_trace(
                    go.Scatter(
                        x=df["ds"],
                        y=df["yhat"],
                        mode="lines",
                        name="Forecast",
                        line=dict(color="#00C853", width=3),
                    )
                )

                # --- FIX 2: Conditional Confidence Intervals ---
                # Only plot these if they exist in the data
                if "yhat_upper" in df.columns and "yhat_lower" in df.columns:
                    fig.add_trace(
                        go.Scatter(
                            x=df["ds"],
                            y=df["yhat_upper"],
                            mode="lines",
                            name="Upper Bound",
                            line=dict(width=0),
                            showlegend=False,
                        )
                    )
                    fig.add_trace(
                        go.Scatter(
                            x=df["ds"],
                            y=df["yhat_lower"],
                            mode="lines",
                            name="Lower Bound",
                            line=dict(width=0),
                            fill="tonexty",
                            fillcolor="rgba(0, 200, 83, 0.1)",
                            showlegend=False,
                        )
                    )
                # -----------------------------------------------

                fig.update_layout(
                    title=f"Energy Demand Forecast ({days} Days)",
                    xaxis_title="Time",
                    yaxis_title="Demand (MW)",
                    template="plotly_dark",
                    height=500,
                )

                st.plotly_chart(fig, use_container_width=True)

                # --- Raw Data ---
                with st.expander("View Raw Data"):
                    st.dataframe(df)

        except Exception as e:
            st.error(f"Error connecting to API: {e}")

# --- Footer ---
st.markdown("---")
st.caption(f"Connected to API: `{API_URL}`")
