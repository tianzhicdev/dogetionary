# SSL Setup with Cloudflare Certificates

## 📋 **Prerequisites**
1. Domain configured in Cloudflare
2. SSL certificate and private key from Cloudflare

## 🔐 **Certificate Setup**

### 1. **Download certificates from Cloudflare:**
   - Go to SSL/TLS → Origin Certificates in Cloudflare dashboard
   - Create/download your origin certificate and private key

### 2. **Place certificates in the correct location:**
   ```bash
   mkdir -p nginx/ssl

   # Copy your Cloudflare certificate and key
   cp your-cloudflare-certificate.pem nginx/ssl/cloudflare.pem
   cp your-cloudflare-private-key.key nginx/ssl/cloudflare.key

   # Set proper permissions
   chmod 600 nginx/ssl/cloudflare.key
   chmod 644 nginx/ssl/cloudflare.pem
   ```

### 3. **Directory structure should look like:**
   ```
   web/
   ├── nginx/
   │   ├── ssl/
   │   │   ├── cloudflare.pem    # Your certificate
   │   │   └── cloudflare.key    # Your private key
   │   ├── default.conf          # HTTP config
   │   └── ssl.conf             # HTTPS config
   ├── docker-compose.yml       # Development
   ├── docker-compose.prod.yml  # Production with SSL
   └── deploy.sh
   ```

## 🚀 **Deployment Commands**

### **Development (HTTP only):**
```bash
docker-compose up -d
```

### **Production (with SSL):**
```bash
# Make sure certificates are in place
ls -la nginx/ssl/

# Deploy with SSL
docker-compose -f docker-compose.prod.yml up -d
```

### **Deploy script with SSL:**
```bash
# Edit deploy.sh to use production config
./deploy.sh prod
```

## 🔧 **Cloudflare Settings**

### **Recommended Cloudflare SSL Settings:**
1. **SSL/TLS encryption mode**: Full (strict)
2. **Always Use HTTPS**: On
3. **HTTP Strict Transport Security (HSTS)**: Enabled
4. **Minimum TLS Version**: 1.2

### **DNS Settings:**
- Point your domain to your server IP
- Enable Cloudflare proxy (orange cloud) for DDoS protection

## ✅ **Testing SSL**

```bash
# Test certificate
openssl x509 -in nginx/ssl/cloudflare.pem -text -noout

# Test HTTPS
curl -I https://unforgettable-dictionary.com

# Check SSL grade
# Visit: https://www.ssllabs.com/ssltest/
```

## 🛠️ **Troubleshooting**

### **Common Issues:**
1. **Permission denied**: Check file permissions on certificate files
2. **Certificate mismatch**: Ensure certificate matches your domain
3. **Nginx won't start**: Check nginx error logs: `docker-compose logs web`

### **Check logs:**
```bash
# Web server logs
docker-compose logs web

# Generator logs
docker-compose logs generator

# All logs
docker-compose logs -f
```