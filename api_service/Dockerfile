# 1. Use an official Python base image
FROM python:3.12-slim

# 2. Set the working directory inside the container
WORKDIR /app

# 3. Set environment variables
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

# 4. Install system dependencies (Prophet needs these)
# 4. Install system dependencies (Prophet needs these)
    RUN apt-get update && apt-get install -y \
        gcc \
        g++ \
        build-essential \
        libgomp1 \
        && rm -rf /var/lib/apt/lists/*

# 5. Install Python libraries
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 6. Copy our API code into the container
COPY . .

# 7. Expose the port the app will run on
EXPOSE 8080

# 8. Define the command to run the app
# We use Gunicorn as the production server
CMD ["gunicorn", "-w", "1", "-k", "uvicorn.workers.UvicornWorker", "--timeout", "120", "-b", "0.0.0.0:8080", "main:app"]
