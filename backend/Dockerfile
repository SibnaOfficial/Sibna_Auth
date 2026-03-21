FROM python:3.11-slim

WORKDIR /app

# Install dependencies in a separate layer for caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy source — debug_config.py excluded via .dockerignore
COPY config.py main.py ./

EXPOSE 8000

# Use non-root user in production
RUN adduser --disabled-password --gecos "" sibna
USER sibna

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
