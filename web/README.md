# Unforgettable Dictionary - Static Site Generator

This project generates SEO-optimized static HTML pages for the Unforgettable Dictionary, maximizing Google indexing and organic traffic potential.

## Features

- **SEO-Optimized**: Every page includes proper meta tags, structured data, and Open Graph tags
- **Performance**: Static HTML with minimal CSS/JS for fastest loading
- **Scalable**: Can handle thousands of words with efficient pagination
- **Mobile-First**: Responsive design optimized for all devices
- **Docker Ready**: Easy deployment with Docker and Docker Compose

## Quick Start

1. **Setup Environment**
   ```bash
   cp .env.example .env
   # Edit .env with your API configuration
   ```

2. **Generate Site**
   ```bash
   # Using Docker (recommended)
   docker-compose up generator

   # Or locally
   cd generator
   pip install -r requirements.txt
   python generate.py
   ```

3. **Serve Site**
   ```bash
   # Using Docker
   docker-compose up web

   # Or locally with any static server
   cd dist && python -m http.server 8000
   ```

## Architecture

### Static Site Structure
```
dist/
├── index.html              # Homepage
├── words/                  # Individual word pages
│   ├── a/
│   │   ├── apple.html
│   │   └── ...
│   └── ...
├── letters/                # Letter index pages
│   ├── a.html
│   └── ...
├── sitemap.xml            # XML sitemap
├── robots.txt             # Search engine directives
└── static/                # CSS, JS, images
```

### URL Structure
- Homepage: `/`
- Word pages: `/words/{letter}/{word}.html`
- Letter index: `/letters/{letter}.html`
- Sitemap: `/sitemap.xml`

## SEO Features

### On-Page SEO
- **Title Tags**: Unique, keyword-rich titles for every page
- **Meta Descriptions**: Compelling descriptions under 160 characters
- **Header Structure**: Proper H1-H6 hierarchy
- **Internal Linking**: Smart cross-links between related words

### Technical SEO
- **Schema.org**: DefinedTerm structured data for rich snippets
- **XML Sitemaps**: Auto-generated, split if >50k URLs
- **Robots.txt**: Proper crawl directives
- **Canonical URLs**: Prevent duplicate content issues
- **Clean URLs**: SEO-friendly URL structure

### Performance SEO
- **Static HTML**: Fastest possible loading times
- **Minified Assets**: Compressed HTML, CSS, JS
- **Image Optimization**: WebP support, lazy loading
- **Caching Headers**: Proper browser and CDN caching

## Configuration

### Environment Variables
```bash
# API Configuration
API_BASE_URL=https://dogetionary.webhop.net/api
API_TIMEOUT=30
API_BATCH_SIZE=1000

# Site Settings
SITE_BASE_URL=https://unforgettable-dictionary.com
WORDS_PER_PAGE=100
MAX_SITEMAP_URLS=50000
```

### Generator Options
- **Minification**: HTML/CSS/JS compression
- **Pagination**: Configurable words per page
- **Sitemap Splitting**: Auto-split large sitemaps
- **Related Words**: Auto-generated word relationships

## Deployment

### Production Deployment
1. **VPS Setup**
   ```bash
   # Clone repository
   git clone https://github.com/your-repo/unforgettable-dictionary.git
   cd unforgettable-dictionary/web

   # Setup environment
   cp .env.example .env
   nano .env  # Edit with production values

   # Deploy with Docker
   docker-compose -f docker-compose.prod.yml up -d
   ```

2. **SSL/TLS Setup**
   ```bash
   # Add SSL certificates to nginx/ssl/
   # Update nginx configuration for HTTPS
   ```

3. **Domain Setup**
   - Point DNS A record to your VPS IP
   - Configure domain in nginx config
   - Setup SSL certificates (Let's Encrypt recommended)

### Automated Updates
```bash
# Setup cron job for regular regeneration
0 2 * * * cd /path/to/project && docker-compose up generator
```

## Development

### Local Development
```bash
# Install dependencies
cd generator
pip install -r requirements.txt

# Run generator
python generate.py

# Serve locally
cd ../dist
python -m http.server 8000
```

### Customization
- **Templates**: Edit files in `generator/templates/`
- **Styles**: Modify `static/css/style.css`
- **JavaScript**: Update `static/js/app.js`

## Performance Targets

- **Page Load Speed**: < 1 second
- **Time to First Byte**: < 200ms
- **Lighthouse Score**: 95+ for all metrics
- **Core Web Vitals**: All green

## Analytics & Monitoring

### Google Analytics
Add your GA4 measurement ID to templates:
```javascript
gtag('config', 'GA_MEASUREMENT_ID');
```

### Search Console
1. Verify domain ownership
2. Submit sitemap: `https://your-domain.com/sitemap.xml`
3. Monitor indexing status and search performance

### Monitoring
- **Uptime**: Use services like UptimeRobot
- **Performance**: Monitor Core Web Vitals
- **SEO**: Track rankings and organic traffic

## Content Strategy

### Word Priority
1. **High-frequency words**: Common vocabulary first
2. **Long-tail keywords**: Specific, niche terms
3. **Learning progression**: Beginner to advanced

### Content Quality
- Clear, concise definitions
- Multiple example sentences
- Pronunciation guides (IPA)
- Cultural context when relevant

## Future Enhancements

- [ ] Multi-language support
- [ ] Progressive Web App (PWA)
- [ ] AMP pages for mobile
- [ ] Advanced search functionality
- [ ] User-generated content
- [ ] API for developers

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes and test
4. Submit a pull request

## License

MIT License - see LICENSE file for details