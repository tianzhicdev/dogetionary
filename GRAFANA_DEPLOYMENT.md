# Grafana Access Setup - Deployment Guide

## What Was Changed

### 1. Nginx Configuration (`nginx/default.conf`)
Added reverse proxy for Grafana at `/grafana/` path:
- Proxies requests from `https://kwafy.com/grafana` to internal Grafana container
- Includes WebSocket support for live dashboard updates
- Location: Lines 72-84

### 2. Docker Compose (`docker-compose.yml`)
Updated Grafana environment variables:
- `GF_SERVER_ROOT_URL=https://kwafy.com/grafana` - Sets the base URL
- `GF_SERVER_SERVE_FROM_SUB_PATH=true` - Enables sub-path serving

## How to Deploy

### On Production Server

1. **Pull the latest changes:**
   ```bash
   git pull
   ```

2. **Restart services in correct order:**
   ```bash
   # Stop nginx first
   docker-compose stop nginx

   # Start/restart grafana
   docker-compose up -d grafana

   # Rebuild and start nginx (after grafana is running)
   docker-compose up -d --build nginx
   ```

3. **Verify it's working:**
   ```bash
   # Check nginx config is valid
   docker-compose exec nginx nginx -t

   # Check both services are running
   docker-compose ps grafana nginx

   # Test the endpoint
   curl -I https://kwafy.com/grafana/login
   ```

## Access Grafana

### Production
- **URL:** `https://kwafy.com/grafana`
- **Username:** `admin`
- **Password:** `admin123`

### Local Development
- **URL:** `http://localhost:3000` (direct) or `http://localhost/grafana` (via nginx)
- **Username:** `admin`
- **Password:** `admin123`

## Testing

After deployment, test the following:

1. **Access the UI:**
   ```bash
   curl -I https://kwafy.com/grafana/login
   ```
   Should return HTTP 200

2. **Check logs if there are issues:**
   ```bash
   docker-compose logs grafana
   docker-compose logs nginx
   ```

## Troubleshooting

### Issue: 404 Not Found
- Verify nginx container restarted: `docker-compose ps nginx`
- Check nginx config: `docker exec dogetionary-nginx-1 nginx -t`
- Check nginx error logs: `docker-compose logs nginx | tail -50`

### Issue: Grafana shows wrong links/redirects
- Verify Grafana environment variables: `docker-compose config | grep -A 5 grafana`
- Restart Grafana: `docker-compose restart grafana`

### Issue: WebSocket connection fails (dashboards not updating)
- Check browser console for errors
- Verify Upgrade headers in nginx config
- Check Grafana logs: `docker-compose logs grafana | tail -50`

## Security Notes

⚠️ **Before production use:**

1. **Change the admin password:**
   ```bash
   # Update docker-compose.yml:
   - GF_SECURITY_ADMIN_PASSWORD=<strong-password-here>

   # Then restart:
   docker-compose restart grafana
   ```

2. **Optional: Restrict access by IP (if only you need access):**
   Add to the nginx `/grafana/` location block:
   ```nginx
   allow YOUR_IP_ADDRESS;
   deny all;
   ```

3. **Consider using Grafana's built-in auth:**
   - Set up OAuth/SSO
   - Enable 2FA
   - Create read-only users for viewers

## What This Solves

✅ Grafana accessible at `https://kwafy.com/grafana`
✅ Works through Cloudflare (uses standard HTTPS port 443)
✅ No need to open port 3000 on firewall
✅ Secured with SSL/TLS
✅ Live dashboard updates via WebSocket

## Alternative: Add Prometheus Too

If you also want Prometheus accessible (currently on port 9090), add to `nginx/default.conf`:

```nginx
# Prometheus proxy
location /prometheus/ {
    proxy_pass http://prometheus:9090/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

Then access at: `https://kwafy.com/prometheus`
