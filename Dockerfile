# Use Python 3.12 slim image
FROM python:3.12-slim

# Set working directory
WORKDIR /app

# Copy project files
COPY pyproject.toml uv.lock* ./
COPY src/ ./src/

# Install uv
RUN pip install --no-cache-dir uv

# Install dependencies
RUN uv sync --frozen

# Expose port
EXPOSE 8000

# Set environment variables
ENV PYTHONUNBUFFERED=1

# Run the Azure Container App streamable HTTP server
CMD ["uv", "run", "python", "src/azureapp_streamable_http_server.py"]
