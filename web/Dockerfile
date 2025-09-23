# Multi-stage build for the static site generator
FROM python:3.11-slim as generator

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy generator requirements and install dependencies
COPY generator/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy generator source code
COPY generator/ ./generator/
COPY static/ ./static/

# Set environment variables
ENV PYTHONPATH=/app
ENV PYTHONUNBUFFERED=1

# Copy environment file (will be mounted in production)
# COPY .env .env

# Generate the static site
RUN mkdir -p /app/dist

# The actual generation will be done by running the script
# CMD ["python", "generator/generate.py"]

# Production stage - Nginx for serving static files
FROM nginx:alpine as production

# Remove default nginx website
RUN rm -rf /usr/share/nginx/html/*

# Copy nginx configuration
COPY nginx/default.conf /etc/nginx/conf.d/default.conf

# Copy static files from generator stage
COPY --from=generator /app/dist /usr/share/nginx/html
COPY --from=generator /app/static /usr/share/nginx/html/static

# Add custom nginx configuration for SEO
RUN echo 'server_tokens off;' >> /etc/nginx/nginx.conf

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

# Install curl for healthcheck
RUN apk add --no-cache curl

# Expose port
EXPOSE 80

# Start nginx
CMD ["nginx", "-g", "daemon off;"]