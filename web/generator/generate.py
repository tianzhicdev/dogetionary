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

        # Add Python built-ins to Jinja2 globals
        self.jinja_env.globals['max'] = max
        self.jinja_env.globals['min'] = min

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

    def generate_meta_description(self, word: str, definition_data: Dict) -> str:
        """
        Generate optimized meta description for SEO.
        Format: Word: Core definition (50-80 chars). Key feature (20-40 chars). Pronunciation (20 chars).
        Total: 150-160 characters
        """
        if not definition_data.get('definitions'):
            return f"{word}: No definition available."

        first_def = definition_data['definitions'][0]
        full_definition = first_def.get('definition', '')
        part_of_speech = first_def.get('type', '')
        phonetic = definition_data.get('phonetic', '')
        examples = first_def.get('examples', [])

        # Calculate available space
        word_prefix = f"{word}: "
        available_space = 160 - len(word_prefix)

        # Prepare pronunciation (if available, ~15-25 chars including "Pron: ")
        pronunciation = ""
        if phonetic:
            pronunciation = f" Pron: {phonetic}"
            if len(pronunciation) > 25:
                pronunciation = pronunciation[:23]

        # Prepare feature (part of speech, ~7-15 chars)
        feature = ""
        if part_of_speech:
            feature = f" ({part_of_speech})"

        # Calculate space for core definition
        fixed_parts_length = len(feature) + len(pronunciation)
        definition_space = available_space - fixed_parts_length

        # Extract and trim core definition to fit remaining space
        core_def = full_definition
        if len(core_def) > definition_space:
            # Try to cut at sentence boundary
            cutoff = core_def[:definition_space-3].rfind('.')
            if cutoff > definition_space * 0.6:  # Use sentence break if it's not too short
                core_def = core_def[:cutoff+1]
            else:
                # Try to cut at clause boundary (comma)
                cutoff = core_def[:definition_space-3].rfind(',')
                if cutoff > definition_space * 0.6:
                    core_def = core_def[:cutoff]
                else:
                    # Cut at word boundary
                    cutoff = core_def[:definition_space-3].rfind(' ')
                    if cutoff > 0:
                        core_def = core_def[:cutoff]
                    else:
                        core_def = core_def[:definition_space-3]

        # Build initial description
        description = word_prefix + core_def + feature + pronunciation

        # If description is too short (< 140 chars), try to add context
        if len(description) < 140 and examples:
            # Try to add a short example fragment
            remaining_space = 158 - len(description)  # Leave 2 chars for safety
            if remaining_space > 20:  # Only add if we have meaningful space
                example_intro = " Ex: "
                example_space = remaining_space - len(example_intro)
                if example_space > 15:  # Minimum useful example length
                    example_text = examples[0]
                    if len(example_text) > example_space:
                        # Trim example to fit
                        cutoff = example_text[:example_space-3].rfind(' ')
                        if cutoff > 0:
                            example_text = example_text[:cutoff] + "..."
                        else:
                            example_text = example_text[:example_space-3] + "..."
                    description += example_intro + example_text

        # Ensure we're within limits (150-160 chars is ideal)
        if len(description) > 160:
            # Need to trim more aggressively
            excess = len(description) - 160
            if len(pronunciation) > 0:
                # Try removing pronunciation first
                description = word_prefix + core_def + feature
                if len(description) <= 160:
                    return description

            # Still too long, trim definition more
            new_def_space = definition_space - excess - 3
            cutoff = core_def[:new_def_space].rfind(' ')
            if cutoff > 0:
                core_def = core_def[:cutoff] + "..."
            else:
                core_def = core_def[:new_def_space] + "..."
            description = word_prefix + core_def + feature

        return description

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

            # Find related words (same first 3 letters and same language pair)
            related_words = [
                w['word'] for w in all_words
                if w['word'].lower().startswith(word[:3])
                and w['word'].lower() != word
                and w['learning_language'] == word_data['learning_language']
                and w['native_language'] == word_data['native_language']
            ][:5]  # Limit to 5 related words

            # Navigation - filter by same language pair
            same_lang_words = [
                (idx, w) for idx, w in enumerate(all_words)
                if w['learning_language'] == word_data['learning_language']
                and w['native_language'] == word_data['native_language']
            ]

            # Find current word's position in same-language list
            current_pos = next((idx for idx, (orig_idx, w) in enumerate(same_lang_words) if orig_idx == i), None)

            prev_word = same_lang_words[current_pos-1][1]['word'] if current_pos and current_pos > 0 else None
            next_word = same_lang_words[current_pos+1][1]['word'] if current_pos is not None and current_pos < len(same_lang_words) - 1 else None

            # Generate optimized meta description
            meta_description = self.generate_meta_description(
                word_data['word'],
                word_data['definition_data']
            )

            context = {
                'word': word_data,
                'definition_data': word_data['definition_data'],
                'meta_description': meta_description,
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

    def generate_homepage(self):
        """Generate homepage - app introduction"""
        logger.info("Generating homepage...")

        # Fetch summary data
        summary = self.fetch_words_summary()

        context = {
            'total_words': summary.get('total_words', self.stats['total_words']),
            'total_definitions': summary.get('total_definitions', self.stats['total_definitions']),
            'language_pairs': summary.get('language_pairs', []),
            'site_config': self.site_config
        }

        output_path = self.dist_dir / 'index.html'
        self.render_and_save('home.html', context, output_path)

        logger.info("Generated homepage")

    def generate_language_pair_pages(self, all_words: List[Dict]):
        """Generate language pair index pages like /en/zh"""
        logger.info("Generating language pair pages...")

        # Group words by language pair
        language_pairs = {}
        for word_data in all_words:
            learning = word_data['learning_language']
            native = word_data['native_language']
            pair_key = f"{learning}/{native}"

            if pair_key not in language_pairs:
                language_pairs[pair_key] = []

            language_pairs[pair_key].append(word_data)

        # Generate index page for each language pair
        for pair_key, words in language_pairs.items():
            learning_lang, native_lang = pair_key.split('/')

            # Sort words alphabetically
            words.sort(key=lambda x: x['word'].lower())

            # Group by first letter for the index
            letter_groups = {}
            for word in words:
                first_letter = word['word'][0].lower()
                if first_letter not in letter_groups:
                    letter_groups[first_letter] = []
                letter_groups[first_letter].append(word)

            context = {
                'learning_language': learning_lang,
                'native_language': native_lang,
                'total_words': len(words),
                'letter_groups': dict(sorted(letter_groups.items())),
                'words': words[:100],  # Show first 100 words on index
                'site_config': self.site_config
            }

            # Create language pair directory
            lang_pair_dir = self.dist_dir / learning_lang / native_lang
            lang_pair_dir.mkdir(parents=True, exist_ok=True)

            output_path = lang_pair_dir / 'index.html'
            self.render_and_save('language_pair.html', context, output_path)

            logger.info(f"Generated language pair page: {pair_key} ({len(words)} words)")

        logger.info(f"Generated {len(language_pairs)} language pair pages")

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

        # Language pair pages (e.g., /en/zh)
        language_pairs = set()
        for letter_words in grouped_words.values():
            for word_data in letter_words:
                pair = (word_data['learning_language'], word_data['native_language'])
                language_pairs.add(pair)

        for learning_lang, native_lang in language_pairs:
            urls.append({
                'url': f"{base_url}/{learning_lang}/{native_lang}/",
                'lastmod': datetime.now().strftime('%Y-%m-%d'),
                'priority': '0.9',
                'changefreq': 'weekly'
            })

        # Letter pages
        for letter in grouped_words.keys():
            urls.append({
                'url': f"{base_url}/letters/{letter}.html",
                'lastmod': datetime.now().strftime('%Y-%m-%d'),
                'priority': '0.7',
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
        all_words = self.fetch_all_words()
        grouped_words = self.process_word_data(all_words)

        # Setup
        self.create_directories()
        self.copy_static_files()

        # Generate pages
        self.generate_homepage()
        self.generate_language_pair_pages(all_words)
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