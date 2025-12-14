FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Create logs directory for Gunicorn
RUN mkdir -p /app/logs

EXPOSE 5000

# Use Gunicorn production WSGI server
# --config: Load configuration from gunicorn.conf.py
# app:app: Points to the 'app' variable in app.py created by create_app()
CMD ["gunicorn", "--config", "gunicorn.conf.py", "app:app"]