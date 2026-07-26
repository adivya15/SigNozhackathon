# syntax=docker/dockerfile:1

FROM python:3.11-slim

# Set working directory
WORKDIR /code

# Install system dependencies
RUN apt-get update && \
    apt-get install -y tesseract-ocr && \
    rm -rf /var/lib/apt/lists/*

# Copy requirements first (better Docker layer caching)
COPY requirements.txt .

# Install Python dependencies
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --timeout=120 --retries 5 -r requirements.txt

# Download embedding model during image build
RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('sentence-transformers/multi-qa-MiniLM-L6-cos-v1')"

# Copy application source
COPY ./app ./app

# Create directory for embedded Chroma database
RUN mkdir -p /code/chroma_db

# Expose FastAPI port
EXPOSE 8000

# Start FastAPI
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]