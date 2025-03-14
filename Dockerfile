FROM python:3.9-slim AS builder

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Create and set working directory
WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Final stage - Use a clean image
FROM python:3.9-slim

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Create a non-root user
RUN useradd -m -U folksonomy

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    netcat-openbsd \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Create and set working directory
WORKDIR /app

# Copy the built dependencies from the builder stage
COPY --from=builder /usr/local/lib/python3.9/site-packages /usr/local/lib/python3.9/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Copy application code
COPY . .

# Create logs directory and give permissions
RUN mkdir -p /app/logs && \
    chown -R folksonomy:folksonomy /app

# Create a startup script
RUN echo '#!/bin/bash\n\
echo "Waiting for PostgreSQL to be ready..."\n\
while ! nc -z $POSTGRES_HOST 5432; do\n\
  sleep 1\n\
done\n\
echo "PostgreSQL is ready!"\n\
\n\
echo "Starting Folksonomy API server..."\n\
uvicorn folksonomy.api:app --host 0.0.0.0 --port 8000 --proxy-headers\n\
' > /app/start.sh && \
    chmod +x /app/start.sh

# Create a database helper script
RUN echo '#!/bin/bash\n\
PGPASSWORD=$POSTGRES_PASSWORD psql -h $POSTGRES_HOST -U $POSTGRES_USER -d $POSTGRES_DATABASE "$@"\n\
' > /app/db-connect.sh && \
    chmod +x /app/db-connect.sh

# Switch to non-root user
USER folksonomy

# Expose port
EXPOSE 8000

# Start the application
CMD ["/app/start.sh"]