#!/usr/bin/env python3
"""
Unforgettable Dictionary - Static Site Generator

Generates SEO-optimized static HTML pages for all words in the dictionary database.
"""

import os
import sys
import json
import logging
import asyncio
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Any, Optional
from urllib.parse import quote
import requests
from jinja2 import Environment, FileSystemLoader, select_autoescape
import minify_html
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('generation.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

class DictionaryGenerator:
    def __init__(self):
        self.base_dir = Path(__file__).parent
        self.dist_dir = self.base_dir.parent / 'dist'
        self.templates_dir = self.base_dir / 'templates'
        self.static_dir = self.base_dir.parent / 'static'

        # API configuration
        self.api_config = {
            'base_url': os.getenv('API_BASE_URL', 'https://dogetionary.webhop.net/api'),
            'timeout': int(os.getenv('API_TIMEOUT', '30')),
            'batch_size': int(os.getenv('API_BATCH_SIZE', '1000')),
        }

        # Debug: print the API configuration
        logger.info(f"API Configuration: {self.api_config}")

        # Site configuration
        self.site_config = {
            'base_url': 'https://unforgettable-dictionary.com',
            'words_per_page': 100,
            'max_sitemap_urls': 50000,
            'minify_html': True,
            'enable_gzip': True
        }

        # Initialize Jinja2 environment
        self.jinja_env = Environment(
            loader=FileSystemLoader(self.templates_dir),
            autoescape=select_autoescape(['html', 'xml']),
            trim_blocks=True,
            lstrip_blocks=True
        )

        self.stats = {
            'total_words': 0,
            'total_pages': 0,
            'total_definitions': 0,
            'language_pairs': set(),
            'generation_time': None
        }

    def make_api_request(self, endpoint: str, params: Dict = None) -> Dict:
        """Make API request with error handling"""
        url = f"{self.api_config['base_url']}/{endpoint.lstrip('/')}"

        try:
            response = requests.get(
                url,
                params=params or {},
                timeout=self.api_config['timeout']
            )
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            logger.error(f"API request failed: {url} - {e}")
            raise

    def fetch_all_words(self) -> List[Dict[str, Any]]:
        """Fetch all words from the API"""
        logger.info("Fetching all words from API...")

        all_words = []
        page = 1
        batch_size = self.api_config['batch_size']

        while True:
            try:
                params = {
                    'page': page,
                    'limit': batch_size,
                    'include_metadata': 'true'
                }

                response = self.make_api_request('words', params)
                words_batch = response.get('words', [])

                if not words_batch:
                    break

                all_words.extend(words_batch)

                pagination = response.get('pagination', {})
                logger.info(f"Fetched page {page}/{pagination.get('total_pages', '?')} - {len(words_batch)} words")

                if not pagination.get('has_next', False):
                    break

                page += 1

            except Exception as e:
                logger.error(f"Failed to fetch words at page {page}: {e}")
                if page == 1:  # If first page fails, abort
                    raise
                else:  # If later page fails, continue with what we have
                    logger.warning(f"Continuing with {len(all_words)} words fetched so far")
                    break

        logger.info(f"Fetched {len(all_words)} word definitions from API")
        return all_words

    def fetch_words_summary(self) -> Dict[str, Any]:
        """Fetch summary statistics from API"""
        try:
            response = self.make_api_request('words/summary')
            logger.info("Fetched words summary from API")
            return response
        except Exception as e:
            logger.error(f"Failed to fetch words summary: {e}")
            # Return default values if API fails
            return {
                'total_words': 0,
                'total_definitions': 0,
                'language_pairs': [],
                'letter_distribution': {},
                'last_updated': None
            }

    def fetch_featured_words(self, count: int = 6) -> List[Dict[str, Any]]:
        """Fetch featured words from API"""
        try:
            params = {'count': count}  # Remove seed for now to avoid issues
            response = self.make_api_request('words/featured', params)
            featured_words = response.get('featured_words', [])
            logger.info(f"Fetched {len(featured_words)} featured words from API")
            return featured_words
        except Exception as e:
            logger.error(f"Failed to fetch featured words: {e}")
            return []

    def process_word_data(self, words: List[Dict]) -> Dict[str, List[Dict]]:
        """Process and group words by first letter"""
        grouped_words = {}

        for word_entry in words:
            word = word_entry['word'].lower()
            first_letter = word[0] if word else 'a'

            if first_letter not in grouped_words:
                grouped_words[first_letter] = []

            # Definition data is already parsed from API
            definition_data = word_entry['definition_data']

            # Process word data
            processed_word = {
                'word': word_entry['word'],
                'learning_language': word_entry['learning_language'],
                'native_language': word_entry['native_language'],
                'definition_data': definition_data,
                'phonetic': definition_data.get('phonetic'),
                'short_definition': self.extract_short_definition(definition_data),
                'created_at': word_entry.get('created_at'),
                'updated_at': word_entry.get('updated_at')
            }

            grouped_words[first_letter].append(processed_word)

            # Update stats
            self.stats['language_pairs'].add(f"{word_entry['learning_language']}-{word_entry['native_language']}")
            if definition_data.get('definitions'):
                self.stats['total_definitions'] += len(definition_data['definitions'])

        self.stats['total_words'] = len(words)
        logger.info(f"Grouped words into {len(grouped_words)} letter categories")

        return grouped_words

    def extract_short_definition(self, definition_data: Dict) -> str:
        """Extract a short definition for previews"""
        if not definition_data.get('definitions'):
            return ""

        first_def = definition_data['definitions'][0]
        definition = first_def.get('definition', '')

        # Truncate to reasonable length
        if len(definition) > 120:
            definition = definition[:117] + "..."

        return definition

    def create_directories(self):
        """Create necessary directories"""
        directories = [
            self.dist_dir,
            self.dist_dir / 'words',
            self.dist_dir / 'letters',
            self.dist_dir / 'static' / 'css',
            self.dist_dir / 'static' / 'js',
            self.dist_dir / 'static' / 'images'
        ]

        # Create language-specific word directories
        # We'll create these dynamically based on actual language pairs
        for directory in directories:
            directory.mkdir(parents=True, exist_ok=True)

        logger.info("Created directory structure")

    def copy_static_files(self):
        """Copy static assets to dist directory"""
        import shutil

        static_src = self.static_dir
        static_dest = self.dist_dir / 'static'

        if static_src.exists():
            # Copy CSS files
            css_src = static_src / 'css'
            css_dest = static_dest / 'css'
            if css_src.exists():
                shutil.copytree(css_src, css_dest, dirs_exist_ok=True)

            # Copy JS files
            js_src = static_src / 'js'
            js_dest = static_dest / 'js'
            if js_src.exists():
                shutil.copytree(js_src, js_dest, dirs_exist_ok=True)

            # Copy image files
            img_src = static_src / 'images'
            img_dest = static_dest / 'images'
            if img_src.exists():
                shutil.copytree(img_src, img_dest, dirs_exist_ok=True)

        logger.info("Copied static files")

    def render_and_save(self, template_name: str, context: Dict, output_path: Path):
        """Render template and save to file"""
        template = self.jinja_env.get_template(template_name)
        try:
            html_content = template.render(**context)
        except Exception as e:
            logger.error(f"Template rendering failed for {template_name}: {e}")
            logger.error(f"Context keys: {list(context.keys())}")
            if 'words' in context and context['words']:
                logger.error(f"First word structure: {list(context['words'][0].keys())}")
            raise

        # Minify HTML if enabled
        if self.site_config['minify_html']:
            html_content = minify_html.minify(
                html_content,
                minify_css=True,
                minify_js=True,
                remove_processing_instructions=True,
                do_not_minify_doctype=True
            )

        # Ensure directory exists
        output_path.parent.mkdir(parents=True, exist_ok=True)

        # Write file
        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(html_content)

        self.stats['total_pages'] += 1

    def generate_word_pages(self, grouped_words: Dict[str, List[Dict]]):
        """Generate individual word pages"""
        logger.info("Generating word pages...")

        # Create a flat list of all words for navigation
        all_words = []
        for letter_words in grouped_words.values():
            all_words.extend(letter_words)

        # Sort alphabetically
        all_words.sort(key=lambda x: x['word'].lower())

        for i, word_data in enumerate(all_words):
            word = word_data['word'].lower()
            first_letter = word[0]

            # Find related words (same first 3 letters)
            related_words = [
                w['word'] for w in all_words
                if w['word'].lower().startswith(word[:3]) and w['word'].lower() != word
            ][:5]  # Limit to 5 related words

            # Navigation
            prev_word = all_words[i-1]['word'] if i > 0 else None
            next_word = all_words[i+1]['word'] if i < len(all_words) - 1 else None

            context = {
                'word': word_data,
                'definition_data': word_data['definition_data'],
                'related_words': related_words,
                'prev_word': prev_word,
                'next_word': next_word,
                'site_config': self.site_config
            }

            # Create language-specific directory structure
            lang_dir = self.dist_dir / word_data['learning_language'] / word_data['native_language'] / first_letter
            lang_dir.mkdir(parents=True, exist_ok=True)

            output_path = lang_dir / f"{word}.html"
            self.render_and_save('word.html', context, output_path)

            if (i + 1) % 1000 == 0:
                logger.info(f"Generated {i + 1} word pages...")

        logger.info(f"Generated {len(all_words)} word pages")

    def generate_letter_pages(self, grouped_words: Dict[str, List[Dict]]):
        """Generate letter index pages"""
        logger.info("Generating letter pages...")

        for letter, words in grouped_words.items():
            logger.info(f"Generating pages for letter: '{letter}'")
            # Sort words alphabetically
            words.sort(key=lambda x: x['word'].lower())

            # Pagination
            words_per_page = self.site_config['words_per_page']
            total_pages = (len(words) + words_per_page - 1) // words_per_page

            for page in range(1, total_pages + 1):
                start_idx = (page - 1) * words_per_page
                end_idx = start_idx + words_per_page
                page_words = words[start_idx:end_idx]

                # Calculate statistics
                avg_length = sum(len(w['word']) for w in words) / len(words) if words else 0
                common_words_count = len([w for w in words if len(w['word']) <= 6])

                context = {
                    'letter': letter,
                    'words': page_words,
                    'page': page,
                    'total_pages': total_pages,
                    'total_words': len(words),
                    'words_per_page': words_per_page,
                    'common_words_count': common_words_count,
                    'average_length': avg_length,
                    'site_config': self.site_config
                }

                if page == 1:
                    output_path = self.dist_dir / 'letters' / f"{letter}.html"
                else:
                    output_path = self.dist_dir / 'letters' / f"{letter}-{page}.html"

                self.render_and_save('letter.html', context, output_path)

        logger.info(f"Generated letter pages for {len(grouped_words)} letters")

    def generate_homepage(self, grouped_words: Dict[str, List[Dict]]):
        """Generate homepage"""
        logger.info("Generating homepage...")

        # Fetch data from API
        summary = self.fetch_words_summary()
        featured_words = self.fetch_featured_words(6)

        # Popular words (could be based on real data later)
        popular_words = [
            'apple', 'beautiful', 'computer', 'dictionary', 'example',
            'fantastic', 'gorgeous', 'hello', 'important', 'journey'
        ]

        # Letter counts from summary or grouped words
        letter_counts = summary.get('letter_distribution', {})
        if not letter_counts:
            letter_counts = {
                letter.upper(): len(words) for letter, words in grouped_words.items()
            }
        else:
            # Convert to uppercase keys
            letter_counts = {k.upper(): v for k, v in letter_counts.items()}

        context = {
            'featured_words': featured_words,
            'popular_words': popular_words,
            'letter_counts': letter_counts,
            'total_words': summary.get('total_words', self.stats['total_words']),
            'total_definitions': summary.get('total_definitions', self.stats['total_definitions']),
            'language_pairs': len(summary.get('language_pairs', [])) or len(self.stats['language_pairs']),
            'site_config': self.site_config
        }

        output_path = self.dist_dir / 'index.html'
        self.render_and_save('index.html', context, output_path)

        logger.info("Generated homepage")

    def _format_date(self, date_str: str) -> str:
        """Format date string for sitemap"""
        if not date_str:
            return None
        try:
            # Handle ISO format from API
            if 'T' in date_str:
                dt = datetime.fromisoformat(date_str.replace('Z', '+00:00'))
            else:
                dt = datetime.strptime(date_str, '%Y-%m-%d')
            return dt.strftime('%Y-%m-%d')
        except (ValueError, TypeError):
            return None

    def generate_sitemap(self, grouped_words: Dict[str, List[Dict]]):
        """Generate XML sitemap"""
        logger.info("Generating sitemap...")

        urls = []
        base_url = self.site_config['base_url']

        # Homepage
        urls.append({
            'url': base_url,
            'lastmod': datetime.now().strftime('%Y-%m-%d'),
            'priority': '1.0',
            'changefreq': 'daily'
        })

        # Letter pages
        for letter in grouped_words.keys():
            urls.append({
                'url': f"{base_url}/letters/{letter}.html",
                'lastmod': datetime.now().strftime('%Y-%m-%d'),
                'priority': '0.8',
                'changefreq': 'weekly'
            })

        # Word pages
        for letter_words in grouped_words.values():
            for word_data in letter_words:
                word = word_data['word'].lower()
                first_letter = word[0]
                learning_lang = word_data['learning_language']
                native_lang = word_data['native_language']
                urls.append({
                    'url': f"{base_url}/{learning_lang}/{native_lang}/{first_letter}/{quote(word)}.html",
                    'lastmod': self._format_date(word_data.get('updated_at')) or datetime.now().strftime('%Y-%m-%d'),
                    'priority': '0.6',
                    'changefreq': 'monthly'
                })

        # Generate sitemap XML
        sitemap_template = self.jinja_env.from_string('''<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
{% for url in urls %}
    <url>
        <loc>{{ url.url }}</loc>
        <lastmod>{{ url.lastmod }}</lastmod>
        <priority>{{ url.priority }}</priority>
        <changefreq>{{ url.changefreq }}</changefreq>
    </url>
{% endfor %}
</urlset>''')

        # Split into multiple sitemaps if needed
        max_urls = self.site_config['max_sitemap_urls']
        if len(urls) <= max_urls:
            sitemap_content = sitemap_template.render(urls=urls)
            with open(self.dist_dir / 'sitemap.xml', 'w', encoding='utf-8') as f:
                f.write(sitemap_content)
        else:
            # Create sitemap index
            sitemap_files = []
            for i in range(0, len(urls), max_urls):
                chunk_urls = urls[i:i + max_urls]
                sitemap_num = (i // max_urls) + 1
                sitemap_filename = f'sitemap-{sitemap_num}.xml'

                sitemap_content = sitemap_template.render(urls=chunk_urls)
                with open(self.dist_dir / sitemap_filename, 'w', encoding='utf-8') as f:
                    f.write(sitemap_content)

                sitemap_files.append({
                    'url': f"{base_url}/{sitemap_filename}",
                    'lastmod': datetime.now().strftime('%Y-%m-%d')
                })

            # Generate sitemap index
            index_template = self.jinja_env.from_string('''<?xml version="1.0" encoding="UTF-8"?>
<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
{% for sitemap in sitemaps %}
    <sitemap>
        <loc>{{ sitemap.url }}</loc>
        <lastmod>{{ sitemap.lastmod }}</lastmod>
    </sitemap>
{% endfor %}
</sitemapindex>''')

            index_content = index_template.render(sitemaps=sitemap_files)
            with open(self.dist_dir / 'sitemap.xml', 'w', encoding='utf-8') as f:
                f.write(index_content)

        logger.info(f"Generated sitemap with {len(urls)} URLs")

    def generate_robots_txt(self):
        """Generate robots.txt"""
        robots_content = f"""User-agent: *
Allow: /

# Sitemap location
Sitemap: {self.site_config['base_url']}/sitemap.xml

# Crawl delay (be nice to servers)
Crawl-delay: 1

# Block non-essential paths
Disallow: /static/
Disallow: /*.json$
Disallow: /*.log$
"""

        with open(self.dist_dir / 'robots.txt', 'w', encoding='utf-8') as f:
            f.write(robots_content)

        logger.info("Generated robots.txt")

    def generate_additional_pages(self):
        """Generate additional SEO pages"""
        # About page
        about_content = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>About Unforgettable Dictionary</title>
    <meta name="description" content="Learn about Unforgettable Dictionary - your comprehensive language learning companion with definitions, pronunciations, and memorable examples.">
</head>
<body>
    <h1>About Unforgettable Dictionary</h1>
    <p>Unforgettable Dictionary is a comprehensive language learning resource designed to help you master vocabulary through clear definitions, accurate pronunciations, and memorable example sentences.</p>
</body>
</html>"""

        with open(self.dist_dir / 'about.html', 'w', encoding='utf-8') as f:
            f.write(about_content)

    async def generate_site(self):
        """Main generation process"""
        start_time = datetime.now()
        logger.info("Starting static site generation...")

        # Fetch data
        words = self.fetch_all_words()
        grouped_words = self.process_word_data(words)

        # Setup
        self.create_directories()
        self.copy_static_files()

        # Generate pages
        self.generate_homepage(grouped_words)
        self.generate_letter_pages(grouped_words)
        self.generate_word_pages(grouped_words)

        # Generate SEO files
        self.generate_sitemap(grouped_words)
        self.generate_robots_txt()
        self.generate_additional_pages()

        # Calculate stats
        end_time = datetime.now()
        self.stats['generation_time'] = end_time - start_time

        logger.info(f"""
Generation Complete!
==================
Total Words: {self.stats['total_words']}
Total Pages: {self.stats['total_pages']}
Total Definitions: {self.stats['total_definitions']}
Language Pairs: {len(self.stats['language_pairs'])}
Generation Time: {self.stats['generation_time']}
Output Directory: {self.dist_dir}
""")

def main():
    """Main entry point"""
    generator = DictionaryGenerator()

    try:
        asyncio.run(generator.generate_site())
    except KeyboardInterrupt:
        logger.info("Generation cancelled by user")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Generation failed: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()