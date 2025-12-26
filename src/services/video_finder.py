"""
VideoFinder Service - Refactored 3-Stage video discovery pipeline

Stage 1: Search ClipCafe for video metadata
Stage 2: Score-based filtering using metadata transcript + LLM (BEFORE download)
Stage 3: Word mapping extraction using Whisper audio transcript + LLM (AFTER download)

Features:
- Idempotent: Caches all intermediate results, safe to resume
- Quality filtering: Score videos before download to save bandwidth
- Audio-verified word mappings: Extract words from Whisper transcript only
- Centralized LLM utility: Uses llm_completion_with_fallback from utils.llm
"""

import os
import json
import base64
import time
import re
import logging
import subprocess
from pathlib import Path
from typing import List, Dict, Optional
from datetime import datetime
import requests

logger = logging.getLogger(__name__)


class VideoFinder:
    """Main class for video discovery and upload pipeline"""

    def __init__(
        self,
        storage_dir: str,
        word_list_path: Optional[str],
        clipcafe_api_key: str,
        openai_api_key: str,
        max_videos_per_word: int = 100,
        education_min_score: float = 0.6,
        context_min_score: float = 0.6,
        max_mappings_per_video: int = 5,
        download_only: bool = False
    ):
        self.storage_dir = Path(storage_dir)
        self.word_list_path = Path(word_list_path) if word_list_path else None
        self.clipcafe_api_key = clipcafe_api_key
        self.openai_api_key = openai_api_key
        self.max_videos_per_word = max_videos_per_word
        self.education_min_score = education_min_score
        self.context_min_score = context_min_score
        self.max_mappings_per_video = max_mappings_per_video
        self.download_only = download_only

        # Generate unique source_id for this pipeline run
        self.source_id = f"find_videos_{datetime.now().strftime('%Y%m%d_%H%M%S')}"

        # Create storage directory if it doesn't exist
        self.storage_dir.mkdir(parents=True, exist_ok=True)

    def fetch_bundle_words(self, bundle_name: str) -> List[str]:
        """Fetch words from bundle that need videos (direct DB query)"""
        try:
            from handlers.admin_videos import BUNDLE_COLUMN_MAP
            from utils.database import db_fetch_all

            # Validate bundle name
            if bundle_name not in BUNDLE_COLUMN_MAP:
                raise ValueError(f"Invalid bundle name '{bundle_name}'. Valid bundles: {', '.join(BUNDLE_COLUMN_MAP.keys())}")

            column_name = BUNDLE_COLUMN_MAP[bundle_name]

            # Query words from bundle that don't have videos
            query = f"""
                SELECT bv.word
                FROM bundle_vocabularies bv
                WHERE bv.{column_name} = TRUE
                  AND NOT EXISTS (
                      SELECT 1
                      FROM word_to_video wtv
                      WHERE wtv.word = bv.word
                        AND wtv.learning_language = bv.language
                  )
                ORDER BY bv.word
            """

            rows = db_fetch_all(query)
            words = [row['word'] for row in rows]

            logger.info(f"Fetched {len(words)} words needing videos from bundle '{bundle_name}'")
            return words

        except Exception as e:
            logger.error(f"Failed to fetch bundle words: {e}")
            raise

    def load_words(self) -> List[str]:
        """Load words from CSV file"""
        import csv
        words = []
        with open(self.word_list_path, 'r') as f:
            reader = csv.reader(f)
            for row in reader:
                if row and row[0].strip():
                    words.append(row[0].strip())

        logger.info(f"Loaded {len(words)} words from {self.word_list_path}")
        return words

    def search_clipcafe(self, word: str) -> List[Dict]:
        """Search ClipCafe API for videos containing word in transcript"""
        logger.info(f"  Searching ClipCafe for '{word}'...")
        params = {
            'api_key': self.clipcafe_api_key,
            'transcript': word,
            'movie_language': 'English',
            'duration': '1-15',
            'sort': 'views',
            'order': 'desc',
            'size': self.max_videos_per_word
        }

        max_retries = 5
        base_delay = 2

        for attempt in range(max_retries):
            try:
                response = requests.get("https://api.clip.cafe/", params=params, timeout=30)

                # Check for rate limiting
                if response.status_code == 429:
                    retry_after = int(response.headers.get('Retry-After', base_delay * (2 ** attempt)))
                    logger.warning(f"  Rate limited by ClipCafe (attempt {attempt+1}/{max_retries}). "
                                 f"Waiting {retry_after}s...")
                    time.sleep(retry_after)
                    continue

                response.raise_for_status()
                data = response.json()

                outer_hits = data.get('hits', {})
                inner_hits = outer_hits.get('hits', [])

                clips = []
                for hit in inner_hits:
                    source = hit.get('_source', {})
                    if source:
                        clips.append(source)

                logger.info(f"  Found {len(clips)} videos for '{word}'")
                return clips

            except requests.exceptions.HTTPError as e:
                if e.response.status_code == 429 and attempt < max_retries - 1:
                    continue
                logger.error(f"  HTTP error searching ClipCafe for '{word}': {e}")
                return []
            except Exception as e:
                if attempt < max_retries - 1:
                    delay = base_delay * (2 ** attempt)
                    logger.warning(f"  Error searching ClipCafe (attempt {attempt+1}/{max_retries}): {e}. "
                                 f"Retrying in {delay}s...")
                    time.sleep(delay)
                else:
                    logger.error(f"  Error searching ClipCafe for '{word}' after {max_retries} attempts: {e}")
                    return []

        return []

    def analyze_scores(self, metadata: Dict, search_word: str) -> Optional[Dict]:
        """
        STAGE 2: Analyze video scores using metadata transcript (BEFORE download).
        Returns education_score and context_score only - no word mappings yet.
        """
        slug = metadata.get('slug', '')
        if not slug:
            return None

        # Validate transcript
        transcript = metadata.get('transcript', '')
        if not transcript or len(transcript.split()) < 10:
            logger.info(f"    Skipping {slug} - transcript too short")
            return None

        # Build LLM prompt for scoring only
        prompt = self._build_score_prompt(metadata)

        # Query LLM using centralized utility
        try:
            llm_response = self._query_llm_centralized(
                prompt=prompt,
                schema_name="video_score_analysis"
            )
        except Exception as e:
            logger.error(f"    LLM query failed for {slug}: {e}")
            return None

        # Extract scores
        education_score = llm_response.get('education_score', 0.0)
        context_score = llm_response.get('context_score', 0.0)

        # Check if video passes thresholds
        if education_score < self.education_min_score:
            logger.debug(f"    Rejecting {slug} - education score too low ({education_score:.2f} < {self.education_min_score})")
            return None

        if context_score < self.context_min_score:
            logger.debug(f"    Rejecting {slug} - context score too low ({context_score:.2f} < {self.context_min_score})")
            return None

        # Build result
        analysis = {
            "slug": slug,
            "search_word": search_word,
            "education_score": round(education_score, 2),
            "context_score": round(context_score, 2),
            "reason": llm_response.get('reason', ''),
            "analyzed_at": datetime.now().isoformat(),
            "stage": "scored"
        }

        logger.info(f"    ✓ {slug} passed scoring (edu={education_score:.2f}, ctx={context_score:.2f})")
        return analysis

    def _build_score_prompt(self, metadata: Dict) -> str:
        """Build LLM prompt for video scoring (education + context only)"""
        transcript = metadata.get('transcript', '')
        movie_title = metadata.get('movie_title', 'Unknown')
        movie_plot = metadata.get('movie_plot', '')[:200]
        duration = metadata.get('duration_seconds', 0)

        prompt = f"""You are an expert ESL teacher analyzing video clips for vocabulary instruction.

VIDEO INFORMATION:
- Title: {movie_title}
- Duration: {duration} seconds
- Plot Context: {movie_plot}...

TRANSCRIPT:
{transcript}

TASK:
Analyze this video clip and evaluate it on TWO criteria for ESL teaching:

1. EDUCATION SCORE (0.0-1.0): How effective is this clip for teaching English vocabulary?
   - Are the words spoken clearly and naturally?
   - Are there likely visual cues that reinforce word meanings?
   - Is the dialogue natural and memorable for learning?
   - Is the vocabulary level appropriate for ESL learners?

2. CONTEXT SCORE (0.0-1.0): Can this scene stand alone without watching the full movie?
   - Does the scene have sufficient context to be understood independently?
   - Would a learner understand what's happening without prior movie knowledge?
   - Is the emotional/narrative context clear from the clip alone?
   - Can the scene work as a self-contained learning moment?

Return ONLY valid JSON (no markdown, no extra text):
{{
  "education_score": 0.85,
  "context_score": 0.70,
  "reason": "Brief 1-2 sentence explanation of why these scores were given"
}}

IMPORTANT:
- Both scores must be between 0.0 and 1.0
- Be conservative - only high-quality clips should score above {self.education_min_score}
- Focus on objective factors, not subjective movie preferences
"""
        return prompt

    def extract_word_mappings(self, metadata: Dict, audio_transcript: Dict, search_word: str) -> Optional[Dict]:
        """
        STAGE 3: Extract word mappings from audio transcript (AFTER download).
        Discovers ALL English words suitable for ESL learning in the verified audio transcript.
        """
        slug = metadata.get('slug', '')
        if not slug:
            return None

        # Get clean audio transcript
        clean_transcript = audio_transcript.get('text', '')
        if not clean_transcript or len(clean_transcript.split()) < 10:
            logger.info(f"      Skipping {slug} - audio transcript too short")
            return None

        # Build prompt for word extraction
        prompt = self._build_word_mapping_prompt(metadata, audio_transcript)

        # Query LLM using centralized utility
        try:
            llm_response = self._query_llm_centralized(
                prompt=prompt,
                schema_name="word_mapping_extraction"
            )
        except Exception as e:
            logger.error(f"      Word mapping LLM query failed for {slug}: {e}")
            return None

        # Validate and filter mappings
        validated_mappings = []
        for mapping in llm_response.get('word_mappings', []):
            word = mapping.get('word', '').strip().lower()

            if not word:
                continue

            # CRITICAL: Validate word exists in AUDIO transcript (prevent LLM hallucination)
            if not re.search(r'\b' + re.escape(word) + r'\b', clean_transcript.lower()):
                logger.warning(f"      Rejecting '{word}' - not in audio transcript (LLM hallucination)")
                continue

            validated_mappings.append({
                "word": word,
                "timestamp": mapping.get('timestamp'),
                "learning_value": mapping.get('learning_value', '')
            })

        if not validated_mappings:
            logger.info(f"      No valid word mappings found for {slug}")
            return None

        # Limit mappings per video
        validated_mappings = validated_mappings[:self.max_mappings_per_video]

        # Build result
        analysis = {
            "slug": slug,
            "search_word": search_word,
            "mappings": validated_mappings,
            "analyzed_at": datetime.now().isoformat(),
            "stage": "word_mapped"
        }

        logger.info(f"      ✓ Found {len(validated_mappings)} word mappings for {slug}")
        return analysis

    def _build_word_mapping_prompt(self, metadata: Dict, audio_transcript: Dict) -> str:
        """Build LLM prompt for word mapping extraction"""
        clean_transcript = audio_transcript.get('text', '')
        movie_title = metadata.get('movie_title', 'Unknown')
        duration = metadata.get('duration_seconds', 0)
        word_timestamps = audio_transcript.get('words', [])

        # Format word timestamps for reference
        timestamp_info = ""
        if word_timestamps:
            timestamp_lines = [f"  {w.get('word', '')}: {w.get('start', 0):.1f}s"
                             for w in word_timestamps[:50]]  # Show first 50 words
            timestamp_info = "\n".join(timestamp_lines)

        prompt = f"""You are an expert ESL teacher extracting vocabulary words from video transcripts.

VIDEO INFORMATION:
- Title: {movie_title}
- Duration: {duration} seconds

AUDIO TRANSCRIPT (verified by Whisper):
{clean_transcript}

WORD TIMESTAMPS (for reference):
{timestamp_info}

TASK:
Extract ALL English words from this transcript that would be valuable for ESL learners.

Focus on words that are:
- Clearly spoken in the audio
- Have educational value (common words, idioms, expressions)
- Natural in context (not awkward or unclear usage)
- Appropriate for ESL learning (not too obscure, not too basic)

For each word, provide:
- word: the vocabulary word (lowercase)
- timestamp: approximate timestamp in seconds (optional, use word timestamp data if available)
- learning_value: 1 sentence explaining why this word is valuable for ESL learners

Return ONLY valid JSON (no markdown, no extra text):
{{
  "word_mappings": [
    {{
      "word": "example",
      "timestamp": 5.2,
      "learning_value": "Common word used naturally in context with clear visual cues"
    }}
  ]
}}

IMPORTANT RULES:
- ONLY suggest words that ACTUALLY APPEAR in the transcript above
- Maximum {self.max_mappings_per_video} words (select the most valuable ones)
- Words must be complete words, not partial matches
- Focus on quality over quantity - only include truly valuable learning words
"""
        return prompt

    def _query_llm_centralized(self, prompt: str, schema_name: str) -> Dict:
        """
        Query LLM using centralized utility with fallback chain.
        Replaces custom _query_llm implementation.
        """
        from utils.llm import llm_completion_with_fallback

        messages = [
            {"role": "system", "content": "You are an ESL teaching expert. Always return valid JSON."},
            {"role": "user", "content": prompt}
        ]

        try:
            # Use centralized LLM utility with video_analysis fallback chain
            result_str = llm_completion_with_fallback(
                messages=messages,
                use_case="video_analysis",
                schema_name=schema_name,
                temperature=0.3,
                max_tokens=800
            )

            if not result_str:
                logger.error("    LLM returned empty response")
                return {}

            # Parse JSON response
            parsed = json.loads(result_str)
            return parsed

        except json.JSONDecodeError as e:
            logger.error(f"    LLM returned invalid JSON: {e}")
            return {}
        except Exception as e:
            logger.error(f"    LLM query failed: {e}")
            return {}

    def extract_audio_transcript(self, video_path: Path, slug: str) -> Optional[Dict]:
        """
        Extract clean audio transcript using Whisper API with word-level timestamps.
        """
        logger.info(f"      Extracting audio transcript with Whisper for {slug}...")

        try:
            # Call Whisper API
            with open(video_path, 'rb') as f:
                headers = {
                    "Authorization": f"Bearer {self.openai_api_key}"
                }
                files = {
                    "file": (f"{slug}.mp4", f, "video/mp4"),
                    "model": (None, "whisper-1"),
                    "response_format": (None, "verbose_json"),
                    "timestamp_granularities[]": (None, "word")
                }

                response = requests.post(
                    "https://api.openai.com/v1/audio/transcriptions",
                    headers=headers,
                    files=files,
                    timeout=120
                )
                response.raise_for_status()

            whisper_result = response.json()

            # Extract clean transcript
            audio_transcript = {
                "text": whisper_result.get("text", ""),
                "words": whisper_result.get("words", []),
                "duration": whisper_result.get("duration", 0),
                "language": whisper_result.get("language", "en"),
                "whisper_metadata": {
                    "segments": whisper_result.get("segments", []),
                    "task": whisper_result.get("task", "transcribe")
                },
                "extracted_at": datetime.now().isoformat()
            }

            logger.info(f"      Whisper transcript extracted: {len(audio_transcript['text'].split())} words, "
                       f"{audio_transcript['duration']:.1f}s")

            return audio_transcript

        except Exception as e:
            logger.error(f"      Failed to extract Whisper transcript for {slug}: {e}")
            return None

    def download_video(self, metadata: Dict) -> Optional[Path]:
        """Download video file from ClipCafe and save to storage"""
        slug = metadata.get('slug', '')
        download_url = metadata.get('download', '')  # ClipCafe provides direct download URL

        if not slug or not download_url:
            logger.error(f"    Missing slug or download URL in metadata")
            return None

        # Create directory for this video
        video_dir = self.storage_dir / slug
        video_dir.mkdir(parents=True, exist_ok=True)

        video_path = video_dir / f"{slug}.mp4"

        # Skip if already downloaded
        if video_path.exists():
            logger.info(f"    Video already exists: {slug}.mp4")
            return video_path

        # Download video from ClipCafe using direct download URL
        logger.info(f"    Downloading {slug}.mp4...")

        try:
            response = requests.get(download_url, timeout=60)
            response.raise_for_status()

            # Save video file
            with open(video_path, 'wb') as f:
                f.write(response.content)

            size_mb = video_path.stat().st_size / (1024 * 1024)
            logger.info(f"    Downloaded {slug}.mp4 ({size_mb:.2f} MB)")
            return video_path

        except Exception as e:
            logger.error(f"    Failed to download video {slug}: {e}")
            return None

    def save_video_to_directory(self, metadata: Dict, analysis: Dict, video_path: Path,
                                audio_transcript: Dict) -> Optional[Dict]:
        """Save video and metadata to directory structure (download-only mode)"""
        slug = metadata.get('slug', '')
        if not slug:
            return None

        video_dir = self.storage_dir / slug

        try:
            # Save metadata
            metadata_path = video_dir / "metadata.json"
            with open(metadata_path, 'w') as f:
                json.dump({
                    "metadata": metadata,
                    "analysis": analysis,
                    "audio_transcript": audio_transcript,
                    "source_id": self.source_id,
                    "saved_at": datetime.now().isoformat()
                }, f, indent=2)

            # Prepare word mappings with proper format
            word_mappings = []
            for m in analysis.get('mappings', []):
                word_mappings.append({
                    "word": m['word'],
                    "learning_language": "en",
                    "relevance_score": 0.8,  # Default since we don't have dual scores anymore
                    "transcript_source": "audio"
                })

            result = {
                "slug": slug,
                "video_path": str(video_path),
                "metadata_path": str(metadata_path),
                "format": "mp4",  # FIXED: was "mp3"
                "mappings": word_mappings
            }

            logger.info(f"      ✓ Saved {slug} to directory")
            return result

        except Exception as e:
            logger.error(f"      Failed to save {slug} to directory: {e}")
            return None

    def upload_to_backend(self, metadata: Dict, analysis: Dict, video_path: Path,
                         audio_transcript: Dict) -> Optional[Dict]:
        """Upload video directly to database using admin_videos handler"""
        slug = metadata.get('slug', '')
        if not slug:
            return None

        try:
            # Read video file and encode as base64
            with open(video_path, 'rb') as f:
                video_bytes = f.read()

            video_base64 = base64.b64encode(video_bytes).decode('utf-8')
            size_bytes = len(video_bytes)
            size_mb = size_bytes / (1024 * 1024)

            # Prepare word mappings from analysis
            # Note: analysis now only has word/timestamp/learning_value from extract_word_mappings
            # We need to get the scores from the earlier stage if needed, or use defaults
            word_mappings = []
            for m in analysis.get('mappings', []):
                word_mappings.append({
                    "word": m['word'],
                    "learning_language": "en",
                    "relevance_score": 0.8,  # Default relevance score
                    "transcript_source": "audio",
                    "timestamp": m.get('timestamp')
                })

            # Prepare video payload
            payload = {
                "videos": [{
                    "slug": slug,
                    "name": slug,
                    "format": "mp4",  # FIXED: was "mp3"
                    "video_data_base64": video_base64,
                    "size_bytes": size_bytes,
                    "transcript": metadata.get('transcript', ''),
                    "audio_transcript": audio_transcript.get('text', ''),
                    "audio_transcript_verified": True,
                    "whisper_metadata": audio_transcript.get('whisper_metadata'),
                    "metadata": {
                        "clip_id": metadata.get('id'),
                        "movie_title": metadata.get('movie_title'),
                        "movie_plot": metadata.get('movie_plot'),
                        "duration_seconds": metadata.get('duration_seconds'),
                        "clipcafe_slug": slug,
                        "analysis": analysis  # Include full analysis for reference
                    },
                    "word_mappings": word_mappings
                }]
            }

            logger.info(f"      Uploading {slug} to database ({size_mb:.2f}MB, {len(word_mappings)} mappings)...")

            # Upload to database directly
            try:
                from handlers.admin_videos import _upload_single_video
                from utils.database import get_db_connection
                import psycopg2.extras

                conn = get_db_connection()
                cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

                try:
                    video_data = payload['videos'][0]
                    result = _upload_single_video(cursor, video_data, self.source_id)
                    conn.commit()

                    logger.info(f"      ✓ Uploaded {slug}: video_id={result['video_id']}, "
                               f"mappings_created={result['mappings_created']}")

                    return result
                except Exception as e:
                    conn.rollback()
                    raise
                finally:
                    cursor.close()
                    conn.close()
            except Exception as e:
                logger.error(f"      ✗ Failed to upload {slug}: {e}")
                return None

        except Exception as e:
            logger.error(f"      Failed to prepare upload for {slug}: {e}")
            return None

    def process_word(self, word: str) -> Dict:
        """Process a single word through the refactored 3-stage pipeline"""
        logger.info(f"\n{'='*60}")
        logger.info(f"Processing word: {word}")
        logger.info(f"{'='*60}")

        word_stats = {
            'word': word,
            'videos_found': 0,
            'scored_videos': 0,
            'downloaded_videos': 0,
            'audio_verified': 0,
            'videos_uploaded': [],
            'mappings_created': []
        }

        # STAGE 1: Search ClipCafe and cache metadata
        logger.info(f"  [Stage 1] Searching ClipCafe for '{word}'...")
        metadata_list = self.search_clipcafe(word)
        word_stats['videos_found'] = len(metadata_list)

        if not metadata_list:
            logger.info(f"  No videos found for '{word}'")
            return word_stats

        logger.info(f"  [Stage 1] Found {len(metadata_list)} videos")

        # STAGE 2: Score-based filtering BEFORE download
        logger.info(f"  [Stage 2] Scoring videos with metadata transcripts (before download)...")
        scored_videos = []
        for metadata in metadata_list:
            score_analysis = self.analyze_scores(metadata, word)
            if score_analysis:
                scored_videos.append((metadata, score_analysis))

        word_stats['scored_videos'] = len(scored_videos)
        logger.info(f"  [Stage 2] {len(scored_videos)} videos passed scoring thresholds")

        if not scored_videos:
            logger.info(f"  No videos passed quality thresholds for '{word}'")
            return word_stats

        # STAGE 3: Download, extract audio, and extract word mappings
        logger.info(f"  [Stage 3] Downloading videos and extracting word mappings...")
        for metadata, score_analysis in scored_videos:
            slug = metadata.get('slug', '')

            # Skip if already exists (idempotency check)
            video_dir = self.storage_dir / slug
            if (video_dir / "metadata.json").exists():
                logger.info(f"    Skipping {slug} - already exists")
                continue

            # Download video
            video_path = self.download_video(metadata)
            if not video_path:
                continue

            word_stats['downloaded_videos'] += 1

            # Extract audio transcript with Whisper
            audio_transcript = self.extract_audio_transcript(video_path, slug)
            if not audio_transcript:
                logger.warning(f"      Failed to extract audio transcript for {slug}")
                continue

            # Extract word mappings from audio transcript
            mapping_analysis = self.extract_word_mappings(metadata, audio_transcript, word)
            if not mapping_analysis or not mapping_analysis.get('mappings'):
                logger.info(f"      No word mappings found for {slug}")
                continue

            word_stats['audio_verified'] += 1

            # Save to directory or upload to backend
            if self.download_only:
                # Download-only mode: save to directory structure
                save_result = self.save_video_to_directory(metadata, mapping_analysis, video_path, audio_transcript)
                if save_result:
                    word_stats['videos_uploaded'].append({
                        'slug': slug,
                        'video_path': save_result.get('video_path'),
                        'metadata_path': save_result.get('metadata_path'),
                        'status': 'saved',
                        'audio_verified': True
                    })
                    word_stats['mappings_created'].extend([
                        {'word': m['word'], 'source': 'audio'}
                        for m in mapping_analysis['mappings']
                    ])
            else:
                # Upload to backend with audio transcript
                upload_result = self.upload_to_backend(metadata, mapping_analysis, video_path, audio_transcript)
                if upload_result:
                    word_stats['videos_uploaded'].append({
                        'slug': slug,
                        'video_id': upload_result.get('video_id'),
                        'status': upload_result.get('status'),
                        'audio_verified': True
                    })
                    word_stats['mappings_created'].extend([
                        {'word': m['word'], 'source': 'audio'}
                        for m in mapping_analysis['mappings']
                    ])

        # Print word summary
        logger.info(f"\n{'='*60}")
        logger.info(f"SUMMARY FOR '{word.upper()}'")
        logger.info(f"{'='*60}")
        logger.info(f"Stage 1 - Videos found: {word_stats['videos_found']}")
        logger.info(f"Stage 2 - Scored (passed): {word_stats['scored_videos']}")
        logger.info(f"Stage 3 - Downloaded: {word_stats['downloaded_videos']}")
        logger.info(f"Stage 3 - Audio verified: {word_stats['audio_verified']}")
        if self.download_only:
            logger.info(f"Videos saved: {len(word_stats['videos_uploaded'])}")
        else:
            logger.info(f"Videos uploaded: {len(word_stats['videos_uploaded'])}")
        logger.info(f"Mappings created: {len(word_stats['mappings_created'])}")

        if word_stats['videos_uploaded']:
            if self.download_only:
                logger.info(f"\nSaved videos (audio-verified):")
                for v in word_stats['videos_uploaded']:
                    logger.info(f"  - {v['slug']} (status={v['status']})")
            else:
                logger.info(f"\nUploaded videos (audio-verified):")
                for v in word_stats['videos_uploaded']:
                    logger.info(f"  - {v['slug']} (video_id={v['video_id']}, status={v['status']})")

        if word_stats['mappings_created']:
            logger.info(f"\nMappings created (from audio transcripts):")
            for m in word_stats['mappings_created']:
                logger.info(f"  - {m['word']} (source={m['source']})")

        logger.info(f"{'='*60}\n")

        return word_stats

    def run(self, words: Optional[List[str]] = None, source_name: Optional[str] = None):
        """Run the complete pipeline"""
        logger.info(f"\n{'='*80}")
        logger.info(f"STARTING VIDEO DISCOVERY PIPELINE")
        logger.info(f"{'='*80}")
        logger.info(f"Mode: {'DOWNLOAD-ONLY' if self.download_only else 'DOWNLOAD + UPLOAD'}")
        logger.info(f"Source ID: {self.source_id}")
        logger.info(f"Storage Dir: {self.storage_dir}")
        logger.info(f"Word Source: {source_name or self.word_list_path}")
        logger.info(f"Max Videos per Word: {self.max_videos_per_word}")
        logger.info(f"Min Education Score: {self.education_min_score}")
        logger.info(f"Min Context Score: {self.context_min_score}")
        logger.info(f"{'='*80}\n")

        # Load words if not provided
        if words is None:
            words = self.load_words()

        # Process each word
        start_time = time.time()
        words_processed = 0
        all_word_stats = []

        for i, word in enumerate(words, 1):
            word_stats = self.process_word(word)
            all_word_stats.append(word_stats)
            words_processed += 1

            logger.info(f"\nProgress: {i}/{len(words)} words ({100*i/len(words):.1f}%)")

        # Final Summary
        elapsed = time.time() - start_time
        total_videos = sum(len(s['videos_uploaded']) for s in all_word_stats)
        total_mappings = sum(len(s['mappings_created']) for s in all_word_stats)

        logger.info(f"\n{'='*80}")
        logger.info(f"PIPELINE COMPLETED")
        logger.info(f"{'='*80}")
        logger.info(f"Source ID: {self.source_id}")
        logger.info(f"Words Processed: {words_processed}")
        logger.info(f"Videos Uploaded: {total_videos}")
        logger.info(f"Mappings Created: {total_mappings}")
        logger.info(f"Time Elapsed: {elapsed/3600:.2f} hours")
        logger.info(f"{'='*80}")
