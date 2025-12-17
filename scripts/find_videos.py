#!/usr/bin/env python3
"""
find_videos.py - 3-Stage video discovery and upload pipeline

Stage 1: Search ClipCafe for video metadata
Stage 2: Candidate selection using metadata transcript + LLM
Stage 3: Audio verification using Whisper API + final LLM analysis

Features:
- Idempotent: Caches all intermediate results, safe to resume
- Parameterized: Storage dir, API domain, word list configurable
- Quality filtering: Whisper audio transcript + dual LLM analysis
- Batch processing: Efficient parallel operations
"""

import os
import sys
import json
import csv
import base64
import time
import re
import argparse
import logging
import subprocess
from pathlib import Path
from typing import List, Dict, Optional, Set
from datetime import datetime
from dotenv import load_dotenv
import requests

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)


class VideoFinder:
    """Main class for video discovery and upload pipeline"""

    def __init__(
        self,
        storage_dir: str,
        backend_url: str,
        word_list_path: Optional[str],
        clipcafe_api_key: str,
        openai_api_key: str,
        max_videos_per_word: int = 100,
        education_min_score: float = 0.6,  # Dual-criteria: education score threshold
        context_min_score: float = 0.6,     # Dual-criteria: context score threshold
        max_mappings_per_video: int = 5,
        download_only: bool = False,
        output_dir: Optional[str] = None
    ):
        self.storage_dir = Path(storage_dir)
        self.backend_url = backend_url.rstrip('/') if backend_url else ''
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

        # Setup directories
        self.metadata_dir = self.storage_dir / "metadata"
        self.candidates_dir = self.storage_dir / "candidates"  # Stage 2: candidate selections
        self.audio_transcripts_dir = self.storage_dir / "audio_transcripts"  # Stage 3: Whisper transcripts
        self.final_analysis_dir = self.storage_dir / "final_analysis"  # Stage 3: final LLM analysis
        self.videos_dir = self.storage_dir / "videos"
        self.state_dir = self.storage_dir / "state"
        self.logs_dir = self.storage_dir / "logs"

        # Output directory for download-only mode
        if output_dir:
            self.output_dir = Path(output_dir)
            self.output_dir.mkdir(parents=True, exist_ok=True)
        else:
            self.output_dir = self.storage_dir / "output"
            self.output_dir.mkdir(parents=True, exist_ok=True)

        for d in [self.metadata_dir, self.candidates_dir, self.audio_transcripts_dir,
                  self.final_analysis_dir, self.videos_dir, self.state_dir, self.logs_dir]:
            d.mkdir(parents=True, exist_ok=True)

        # State tracking for idempotency
        self.processed_words: Set[str] = set()
        self.uploaded_videos: Set[str] = set()
        self.saved_videos: Set[str] = set()  # For download-only mode
        self.failed_uploads: List[Dict] = []

        self._load_state()

    def _load_state(self):
        """Load state from disk to enable resume"""
        processed_file = self.state_dir / "processed_words.txt"
        if processed_file.exists():
            self.processed_words = set(line.strip() for line in open(processed_file) if line.strip())
            logger.info(f"Loaded {len(self.processed_words)} processed words from state")

        uploaded_file = self.state_dir / "uploaded_videos.txt"
        if uploaded_file.exists():
            self.uploaded_videos = set(line.strip() for line in open(uploaded_file) if line.strip())
            logger.info(f"Loaded {len(self.uploaded_videos)} uploaded videos from state")

        saved_file = self.state_dir / "saved_videos.txt"
        if saved_file.exists():
            self.saved_videos = set(line.strip() for line in open(saved_file) if line.strip())
            logger.info(f"Loaded {len(self.saved_videos)} saved videos from state")

    def _save_processed_word(self, word: str):
        """Mark word as processed"""
        self.processed_words.add(word)
        with open(self.state_dir / "processed_words.txt", 'a') as f:
            f.write(f"{word}\n")

    def _save_uploaded_video(self, slug: str):
        """Mark video as uploaded"""
        self.uploaded_videos.add(slug)
        with open(self.state_dir / "uploaded_videos.txt", 'a') as f:
            f.write(f"{slug}\n")

    def _save_failed_upload(self, slug: str, error: str):
        """Record failed upload"""
        entry = {"slug": slug, "error": error, "timestamp": datetime.now().isoformat()}
        self.failed_uploads.append(entry)
        with open(self.state_dir / "failed_uploads.jsonl", 'a') as f:
            f.write(json.dumps(entry) + "\n")

    def fetch_bundle_words(self, bundle_name: str) -> List[str]:
        """Fetch words from bundle via backend API that need videos"""
        try:
            url = f"{self.backend_url}/v3/admin/bundles/{bundle_name}/words-needing-videos"
            logger.info(f"Fetching words from bundle '{bundle_name}' via API: {url}")

            response = requests.get(url, timeout=30)
            response.raise_for_status()

            data = response.json()
            words = data.get('words', [])

            logger.info(f"Fetched {len(words)} words needing videos from bundle '{bundle_name}'")
            return words

        except Exception as e:
            logger.error(f"Failed to fetch bundle words: {e}")
            raise

    def load_words(self) -> List[str]:
        """Load words from CSV file"""
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
        # Check cache first
        cache_dir = self.metadata_dir / word.lower()
        cache_dir.mkdir(parents=True, exist_ok=True)

        cached_files = list(cache_dir.glob("*.json"))
        if cached_files:
            logger.info(f"  Found {len(cached_files)} cached metadata files for '{word}'")
            return [json.load(open(f)) for f in cached_files]

        # Search ClipCafe with retry logic for rate limiting
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
        base_delay = 2  # Start with 2 seconds

        for attempt in range(max_retries):
            try:
                response = requests.get("https://api.clip.cafe/", params=params, timeout=30)

                # Check for rate limiting (429 Too Many Requests)
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

                # Save to cache
                for i, clip in enumerate(clips, 1):
                    slug = clip.get('slug', f'clip_{i}')
                    cache_file = cache_dir / f"{slug}.json"
                    with open(cache_file, 'w', encoding='utf-8') as f:
                        json.dump(clip, f, indent=2, ensure_ascii=False)

                logger.info(f"  Cached {len(clips)} metadata files for '{word}'")
                return clips

            except requests.exceptions.HTTPError as e:
                if e.response.status_code == 429 and attempt < max_retries - 1:
                    # Rate limited, will retry
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

    def find_words_in_transcript(self, transcript: str, vocab_list: List[str]) -> List[str]:
        """Find which vocabulary words appear in the transcript"""
        transcript_lower = transcript.lower()
        candidate_words = []

        for vocab_word in vocab_list:
            # Check if word appears in transcript (case insensitive)
            if re.search(r'\b' + re.escape(vocab_word.lower()) + r'\b', transcript_lower):
                candidate_words.append(vocab_word)

        return candidate_words

    def analyze_candidates(self, metadata: Dict, search_word: str, vocab_list: List[str]) -> Optional[Dict]:
        """
        STAGE 2: Analyze video metadata with LLM to identify candidate videos.
        Uses metadata transcript (ClipCafe) for initial filtering.

        Returns: {"slug": "...", "mappings": [{"word": "...", "relevance_score": 0.95, "reason": "..."}, ...]}
        """
        slug = metadata.get('slug', '')
        if not slug:
            return None

        word_dir = search_word.lower()

        # Check cache first
        cache_file = self.candidates_dir / word_dir / f"{slug}_candidates.json"
        if cache_file.exists():
            logger.info(f"    Using cached candidate analysis for {slug}")
            return json.load(open(cache_file))

        # Validate transcript
        transcript = metadata.get('transcript', '')
        if not transcript or len(transcript.split()) < 10:
            logger.info(f"    Skipping {slug} - transcript too short")
            return None

        # Find candidate words
        candidate_words = self.find_words_in_transcript(transcript, vocab_list)
        if not candidate_words:
            logger.info(f"    Skipping {slug} - no vocabulary words in transcript")
            return None

        # Build LLM prompt
        prompt = self._build_llm_prompt(metadata, candidate_words)

        # Query LLM
        try:
            llm_response = self._query_llm(prompt)
        except Exception as e:
            logger.error(f"    LLM query failed for {slug}: {e}")
            return None

        # Validate and filter mappings
        validated_mappings = []
        for mapping in llm_response.get('mappings', []):
            word = mapping.get('word', '').strip()
            education_score = mapping.get('education_score', 0.0)
            context_score = mapping.get('context_score', 0.0)

            # Validate word is in transcript (prevent LLM hallucination)
            if not re.search(r'\b' + re.escape(word.lower()) + r'\b', transcript.lower()):
                logger.warning(f"    Rejecting '{word}' - not in transcript (LLM hallucination)")
                continue

            # Dual-criteria threshold check
            if education_score < self.education_min_score:
                logger.debug(f"    Rejecting '{word}' - education score too low ({education_score:.2f} < {self.education_min_score})")
                continue

            if context_score < self.context_min_score:
                logger.debug(f"    Rejecting '{word}' - context score too low ({context_score:.2f} < {self.context_min_score})")
                continue

            validated_mappings.append({
                "word": word.lower(),
                "education_score": round(education_score, 2),
                "context_score": round(context_score, 2),
                "reason": mapping.get('reason', '')
            })

        if not validated_mappings:
            logger.info(f"    No quality mappings found for {slug}")
            return None

        # Limit mappings per video (sort by average of education + context scores)
        validated_mappings = sorted(validated_mappings, key=lambda x: (x['education_score'] + x['context_score']) / 2, reverse=True)
        validated_mappings = validated_mappings[:self.max_mappings_per_video]

        # Cache result
        analysis = {
            "slug": slug,
            "search_word": search_word,
            "mappings": validated_mappings,
            "analyzed_at": datetime.now().isoformat(),
            "stage": "candidate"
        }

        cache_file.parent.mkdir(parents=True, exist_ok=True)
        with open(cache_file, 'w', encoding='utf-8') as f:
            json.dump(analysis, f, indent=2, ensure_ascii=False)

        logger.info(f"    Found {len(validated_mappings)} candidate mappings for {slug}")
        return analysis

    def _build_llm_prompt(self, metadata: Dict, candidate_words: List[str]) -> str:
        """Build LLM prompt for video analysis"""
        transcript = metadata.get('transcript', '')
        movie_title = metadata.get('movie_title', 'Unknown')
        movie_plot = metadata.get('movie_plot', '')[:200]
        duration = metadata.get('duration_seconds', 0)

        # Limit candidate words to fit context window
        candidate_words_str = ', '.join(candidate_words[:50])

        prompt = f"""You are an expert ESL teacher analyzing video clips for vocabulary instruction.

VIDEO INFORMATION:
- Title: {movie_title}
- Duration: {duration} seconds
- Plot Context: {movie_plot}...

TRANSCRIPT:
{transcript}

TASK:
Analyze this video and determine which of the following vocabulary words it effectively teaches.

Evaluate each word on TWO separate criteria:

1. EDUCATION SCORE (0.0-1.0): How well does this video illustrate the word's meaning?
   - Does the word appear clearly in the transcript?
   - Are there likely visual cues that reinforce the meaning?
   - Is the usage natural and memorable for learning?

2. CONTEXT SCORE (0.0-1.0): Can this scene stand alone without watching the full movie?
   - Does the scene have sufficient context to be understood independently?
   - Would a learner understand what's happening without prior movie knowledge?
   - Is the emotional/narrative context clear from the clip alone?

CANDIDATE WORDS (only suggest words from this list):
{candidate_words_str}

For each word you recommend, provide:
- word: the vocabulary word
- education_score: 0.0-1.0 (how well the video illustrates the word's meaning)
- context_score: 0.0-1.0 (how well the scene stands alone)
- reason: brief explanation (1-2 sentences)

Return ONLY valid JSON (no markdown, no extra text):
{{
  "mappings": [
    {{
      "word": "example",
      "education_score": 0.85,
      "context_score": 0.70,
      "reason": "Word used clearly with visual cues. Scene needs some movie context to fully understand."
    }}
  ]
}}

IMPORTANT RULES:
- Only suggest words from the candidate list above
- Only suggest words that actually appear in the transcript
- Minimum education_score: {self.education_min_score}
- Minimum context_score: {self.context_min_score}
- Maximum {self.max_mappings_per_video} mappings per video (focus on best matches)
"""
        return prompt

    def _query_llm(self, prompt: str) -> Dict:
        """Query OpenAI API with retry logic"""
        headers = {
            "Authorization": f"Bearer {self.openai_api_key}",
            "Content-Type": "application/json"
        }

        payload = {
            "model": "gpt-4o-mini",
            "messages": [
                {"role": "system", "content": "You are an ESL teaching expert. Always return valid JSON."},
                {"role": "user", "content": prompt}
            ],
            "temperature": 0.3,
            "max_tokens": 800,
            "response_format": {"type": "json_object"}
        }

        for attempt in range(3):
            try:
                response = requests.post(
                    "https://api.openai.com/v1/chat/completions",
                    headers=headers,
                    json=payload,
                    timeout=60
                )
                response.raise_for_status()

                result = response.json()
                content = result['choices'][0]['message']['content']
                return json.loads(content)

            except json.JSONDecodeError as e:
                logger.warning(f"    LLM returned invalid JSON (attempt {attempt+1}): {e}")
                if attempt == 2:
                    return {"mappings": []}
                time.sleep(2)

            except Exception as e:
                logger.warning(f"    LLM API error (attempt {attempt+1}): {e}")
                if attempt == 2:
                    raise
                time.sleep(5)

        return {"mappings": []}

    def extract_audio_transcript(self, video_path: Path, slug: str) -> Optional[Dict]:
        """
        STAGE 3A: Extract clean audio transcript using Whisper API.

        Returns: {"text": "...", "words": [...], "duration": 12.5, "whisper_metadata": {...}}
        """
        # Check cache first
        cache_file = self.audio_transcripts_dir / f"{slug}_whisper.json"
        if cache_file.exists():
            logger.info(f"      Using cached Whisper transcript for {slug}")
            return json.load(open(cache_file))

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

            # Cache result
            with open(cache_file, 'w', encoding='utf-8') as f:
                json.dump(audio_transcript, f, indent=2, ensure_ascii=False)

            logger.info(f"      Whisper transcript extracted: {len(audio_transcript['text'].split())} words, "
                       f"{audio_transcript['duration']:.1f}s")

            return audio_transcript

        except Exception as e:
            logger.error(f"      Failed to extract Whisper transcript for {slug}: {e}")
            return None

    def analyze_final(self, metadata: Dict, audio_transcript: Dict, search_word: str,
                     vocab_list: List[str]) -> Optional[Dict]:
        """
        STAGE 3B: Final analysis using clean audio transcript from Whisper.
        Re-evaluates candidate mappings with accurate transcript.

        Returns: {"slug": "...", "mappings": [...], "audio_verified": True}
        """
        slug = metadata.get('slug', '')
        if not slug:
            return None

        word_dir = search_word.lower()

        # Check cache first
        cache_file = self.final_analysis_dir / word_dir / f"{slug}_final.json"
        if cache_file.exists():
            logger.info(f"      Using cached final analysis for {slug}")
            return json.load(open(cache_file))

        # Get clean audio transcript
        clean_transcript = audio_transcript.get('text', '')
        if not clean_transcript or len(clean_transcript.split()) < 10:
            logger.info(f"      Skipping {slug} - audio transcript too short")
            return None

        # Find candidate words in clean transcript
        candidate_words = self.find_words_in_transcript(clean_transcript, vocab_list)
        if not candidate_words:
            logger.info(f"      Skipping {slug} - no vocabulary words in audio transcript")
            return None

        # Build final LLM prompt with audio transcript
        prompt = self._build_final_llm_prompt(metadata, audio_transcript, candidate_words)

        # Query LLM
        try:
            llm_response = self._query_llm(prompt)
        except Exception as e:
            logger.error(f"      Final LLM query failed for {slug}: {e}")
            return None

        # Validate and filter mappings
        validated_mappings = []
        for mapping in llm_response.get('mappings', []):
            word = mapping.get('word', '').strip()
            education_score = mapping.get('education_score', 0.0)
            context_score = mapping.get('context_score', 0.0)

            # Validate word is in clean audio transcript
            if not re.search(r'\b' + re.escape(word.lower()) + r'\b', clean_transcript.lower()):
                logger.warning(f"      Rejecting '{word}' - not in audio transcript")
                continue

            # Dual-criteria threshold check
            if education_score < self.education_min_score:
                logger.debug(f"      Rejecting '{word}' - education score too low ({education_score:.2f} < {self.education_min_score})")
                continue

            if context_score < self.context_min_score:
                logger.debug(f"      Rejecting '{word}' - context score too low ({context_score:.2f} < {self.context_min_score})")
                continue

            validated_mappings.append({
                "word": word.lower(),
                "education_score": round(education_score, 2),
                "context_score": round(context_score, 2),
                "reason": mapping.get('reason', ''),
                "timestamp": self._find_word_timestamp(word, audio_transcript.get('words', []))
            })

        if not validated_mappings:
            logger.info(f"      No quality mappings found in final analysis for {slug}")
            return None

        # Limit mappings per video (sort by average of education + context scores)
        validated_mappings = sorted(validated_mappings, key=lambda x: (x['education_score'] + x['context_score']) / 2, reverse=True)
        validated_mappings = validated_mappings[:self.max_mappings_per_video]

        # Cache result
        final_analysis = {
            "slug": slug,
            "search_word": search_word,
            "mappings": validated_mappings,
            "audio_verified": True,
            "audio_duration": audio_transcript.get('duration', 0),
            "analyzed_at": datetime.now().isoformat(),
            "stage": "final"
        }

        cache_file.parent.mkdir(parents=True, exist_ok=True)
        with open(cache_file, 'w', encoding='utf-8') as f:
            json.dump(final_analysis, f, indent=2, ensure_ascii=False)

        logger.info(f"      ✓ Final analysis: {len(validated_mappings)} verified mappings for {slug}")
        return final_analysis

    def _build_final_llm_prompt(self, metadata: Dict, audio_transcript: Dict,
                                candidate_words: List[str]) -> str:
        """Build LLM prompt for final analysis with audio transcript"""
        clean_transcript = audio_transcript.get('text', '')
        movie_title = metadata.get('movie_title', 'Unknown')
        movie_plot = metadata.get('movie_plot', '')[:200]
        duration = audio_transcript.get('duration', 0)

        candidate_words_str = ', '.join(candidate_words[:50])

        prompt = f"""You are an expert ESL teacher analyzing video clips for vocabulary instruction.

VIDEO INFORMATION:
- Title: {movie_title}
- Duration: {duration:.1f} seconds
- Plot Context: {movie_plot}...

CLEAN AUDIO TRANSCRIPT (from Whisper API):
{clean_transcript}

TASK:
Analyze this video and determine which of the following vocabulary words it effectively teaches.

Evaluate each word on TWO separate criteria:

1. EDUCATION SCORE (0.0-1.0): How well does this video illustrate the word's meaning?
   - Does the word appear clearly in the audio transcript?
   - Are there likely visual cues that reinforce the meaning?
   - Is the usage natural and memorable for learning?

2. CONTEXT SCORE (0.0-1.0): Can this scene stand alone without watching the full movie?
   - Does the scene have sufficient context to be understood independently?
   - Would a learner understand what's happening without prior movie knowledge?
   - Is the emotional/narrative context clear from the clip alone?

CANDIDATE WORDS (only suggest words from this list):
{candidate_words_str}

For each word you recommend, provide:
- word: the vocabulary word
- education_score: 0.0-1.0 (how well the video illustrates the word's meaning)
- context_score: 0.0-1.0 (how well the scene stands alone)
- reason: brief explanation (1-2 sentences)

Return ONLY valid JSON (no markdown, no extra text):
{{
  "mappings": [
    {{
      "word": "example",
      "education_score": 0.85,
      "context_score": 0.70,
      "reason": "Word used clearly with visual cues. Scene needs some movie context to fully understand."
    }}
  ]
}}

IMPORTANT RULES:
- Only suggest words from the candidate list above
- Only suggest words that actually appear in the clean audio transcript
- This is a VERIFIED audio transcript - be more confident in your assessments
- Minimum education_score: {self.education_min_score}
- Minimum context_score: {self.context_min_score}
- Maximum {self.max_mappings_per_video} mappings per video (focus on best matches)
"""
        return prompt

    def _find_word_timestamp(self, word: str, word_timestamps: List[Dict]) -> Optional[float]:
        """Find timestamp of word in Whisper word-level timestamps"""
        word_lower = word.lower()
        for w in word_timestamps:
            if w.get('word', '').strip().lower() == word_lower:
                return w.get('start', 0)
        return None

    def download_video(self, metadata: Dict) -> Optional[Path]:
        """Download video file and cache locally (max 5MB)"""
        slug = metadata.get('slug', '')
        download_url = metadata.get('download')

        if not slug or not download_url:
            return None

        # Check cache
        video_cache = self.videos_dir / f"{slug}.mp4"
        if video_cache.exists():
            file_size_bytes = video_cache.stat().st_size
            file_size_mb = file_size_bytes / (1024 * 1024)

            # Check size limit even for cached videos
            if file_size_bytes > 5 * 1024 * 1024:
                logger.warning(f"      Skipping cached {slug}.mp4 - too large ({file_size_mb:.2f} MB)")
                return None

            logger.info(f"      Using cached video: {slug}.mp4 ({file_size_mb:.2f} MB)")
            return video_cache

        # Download
        logger.info(f"      Downloading video: {slug}.mp4...")
        try:
            response = requests.get(download_url, stream=True, timeout=60)
            response.raise_for_status()

            with open(video_cache, 'wb') as f:
                for chunk in response.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)

            file_size_bytes = video_cache.stat().st_size
            file_size_mb = file_size_bytes / (1024 * 1024)

            # Check size limit (5MB)
            if file_size_bytes > 5 * 1024 * 1024:
                logger.warning(f"      Skipping {slug}.mp4 - too large ({file_size_mb:.2f} MB)")
                video_cache.unlink()
                return None

            logger.info(f"      Downloaded {slug}.mp4 ({file_size_mb:.2f} MB)")
            return video_cache

        except Exception as e:
            logger.error(f"      Failed to download {slug}: {e}")
            if video_cache.exists():
                video_cache.unlink()
            return None

    def upload_to_backend(self, metadata: Dict, analysis: Dict, video_path: Path,
                          audio_transcript: Optional[Dict] = None) -> Optional[Dict]:
        """Upload video and mappings to backend API with optional audio transcript

        Args:
            metadata: ClipCafe metadata
            analysis: Final LLM analysis with verified mappings
            video_path: Path to video file
            audio_transcript: Optional Whisper audio transcript data

        Returns:
            Upload result dictionary or None if failed
        """
        slug = metadata.get('slug', '')

        # Check if already uploaded (idempotency)
        if slug in self.uploaded_videos:
            logger.info(f"      Skipping upload - {slug} already uploaded")
            return None

        # Read video file
        with open(video_path, 'rb') as f:
            video_bytes = f.read()

        video_base64 = base64.b64encode(video_bytes).decode('utf-8')
        size_bytes = len(video_bytes)

        # Prepare payload
        payload = {
            "source_id": self.source_id,
            "videos": [
                {
                    "slug": slug,
                    "name": slug,
                    "format": "mp4",
                    "video_data_base64": video_base64,
                    "size_bytes": size_bytes,
                    "transcript": metadata.get('transcript', ''),
                    "audio_transcript": audio_transcript.get('text', '') if audio_transcript else None,
                    "audio_transcript_verified": analysis.get('audio_verified', False),
                    "whisper_metadata": audio_transcript.get('whisper_metadata', {}) if audio_transcript else None,
                    "metadata": {
                        "clip_id": metadata.get('clipID'),
                        "duration_seconds": metadata.get('duration'),
                        "resolution": metadata.get('resolution'),
                        "movie_title": metadata.get('movie_title'),
                        "movie_year": metadata.get('movie_year'),
                        "movie_plot": metadata.get('movie_plot'),
                        "views": metadata.get('views'),
                        "likes": metadata.get('likes'),
                        "transcript": metadata.get('transcript'),
                        "subtitles": metadata.get('subtitles'),
                        "imdb_id": metadata.get('imdb'),
                        "audio_duration": audio_transcript.get('duration', 0) if audio_transcript else None,
                    },
                    "word_mappings": [
                        {
                            "word": m['word'],
                            "learning_language": "en",
                            "education_score": m['education_score'],
                            "context_score": m['context_score'],
                            "transcript_source": "audio" if analysis.get('audio_verified') else "metadata",
                            "timestamp": m.get('timestamp')
                        }
                        for m in analysis['mappings']
                    ]
                }
            ]
        }

        # Upload to backend
        try:
            response = requests.post(
                f"{self.backend_url}/v3/admin/videos/batch-upload",
                json=payload,
                timeout=120
            )
            response.raise_for_status()

            result = response.json()
            video_result = result['results'][0]

            logger.info(f"      ✓ Uploaded {slug}: video_id={video_result['video_id']}, "
                       f"mappings_created={video_result['mappings_created']}")

            self._save_uploaded_video(slug)
            return video_result

        except Exception as e:
            logger.error(f"      ✗ Failed to upload {slug}: {e}")
            self._save_failed_upload(slug, str(e))
            return None

    def save_video_to_directory(
        self,
        metadata: Dict,
        analysis: Dict,
        video_path: Path,
        audio_transcript: Optional[Dict] = None
    ) -> Optional[Dict]:
        """
        Save video and metadata to directory structure for download-only mode.

        Directory structure:
        output_dir/
          <video_slug>/
            <video_slug>.mp3      # Extracted audio
            metadata.json         # All metadata including word mappings

        Args:
            metadata: ClipCafe metadata
            analysis: Final LLM analysis with verified mappings
            video_path: Path to video file
            audio_transcript: Optional Whisper audio transcript data

        Returns:
            Result dictionary or None if failed
        """
        slug = metadata.get('slug', '')

        # Check if already saved (idempotency)
        if slug in self.saved_videos:
            logger.info(f"      Skipping save - {slug} already saved")
            return None

        # Create video directory
        video_dir = self.output_dir / slug
        video_dir.mkdir(parents=True, exist_ok=True)

        # Extract MP3 audio from MP4 video
        mp3_path = video_dir / f"{slug}.mp3"
        try:
            logger.info(f"      Extracting MP3 audio: {slug}.mp3...")
            subprocess.run([
                'ffmpeg',
                '-i', str(video_path),
                '-vn',  # No video
                '-acodec', 'libmp3lame',
                '-q:a', '2',  # High quality
                '-y',  # Overwrite
                str(mp3_path)
            ], check=True, capture_output=True, text=True)

            mp3_size_mb = mp3_path.stat().st_size / (1024 * 1024)
            logger.info(f"      ✓ Extracted {slug}.mp3 ({mp3_size_mb:.2f} MB)")

        except subprocess.CalledProcessError as e:
            logger.error(f"      ✗ Failed to extract MP3 for {slug}: {e.stderr}")
            return None
        except Exception as e:
            logger.error(f"      ✗ Failed to extract MP3 for {slug}: {e}")
            return None

        # Prepare metadata.json
        metadata_file = video_dir / "metadata.json"
        metadata_content = {
            "slug": slug,
            "name": slug,
            "format": "mp3",
            "source_id": self.source_id,
            "transcript": metadata.get('transcript', ''),
            "audio_transcript": audio_transcript.get('text', '') if audio_transcript else None,
            "audio_transcript_verified": analysis.get('audio_verified', False),
            "whisper_metadata": audio_transcript.get('whisper_metadata', {}) if audio_transcript else None,
            "clipcafe_metadata": {
                "clip_id": metadata.get('clipID'),
                "duration_seconds": metadata.get('duration'),
                "resolution": metadata.get('resolution'),
                "movie_title": metadata.get('movie_title'),
                "movie_year": metadata.get('movie_year'),
                "movie_plot": metadata.get('movie_plot'),
                "views": metadata.get('views'),
                "likes": metadata.get('likes'),
                "transcript": metadata.get('transcript'),
                "subtitles": metadata.get('subtitles'),
                "imdb_id": metadata.get('imdb'),
                "audio_duration": audio_transcript.get('duration', 0) if audio_transcript else None,
            },
            "word_mappings": [
                {
                    "word": m['word'],
                    "learning_language": "en",
                    "education_score": m['education_score'],
                    "context_score": m['context_score'],
                    "transcript_source": "audio" if analysis.get('audio_verified') else "metadata",
                    "timestamp": m.get('timestamp')
                }
                for m in analysis['mappings']
            ]
        }

        # Save metadata.json
        try:
            with open(metadata_file, 'w') as f:
                json.dump(metadata_content, f, indent=2)

            logger.info(f"      ✓ Saved metadata.json with {len(analysis['mappings'])} word mappings")

            # Mark as saved
            self._save_saved_video(slug)

            return {
                "slug": slug,
                "mp3_path": str(mp3_path),
                "metadata_path": str(metadata_file),
                "mappings_count": len(analysis['mappings'])
            }

        except Exception as e:
            logger.error(f"      ✗ Failed to save metadata for {slug}: {e}")
            return None

    def _save_saved_video(self, slug: str):
        """Mark video as saved to directory (download-only mode)"""
        self.saved_videos.add(slug)
        saved_file = self.state_dir / "saved_videos.txt"
        with open(saved_file, 'a') as f:
            f.write(f"{slug}\n")

    def process_word(self, word: str, vocab_list: List[str]) -> Dict:
        """Process a single word through the 3-stage pipeline

        Stage 1: Search ClipCafe for video metadata
        Stage 2: Candidate selection using metadata transcript + LLM
        Stage 3: Audio verification using Whisper API + final LLM analysis

        Returns:
            Dictionary with stats about processing results
        """
        logger.info(f"\n{'='*60}")
        logger.info(f"Processing word: {word}")
        logger.info(f"{'='*60}")

        word_stats = {
            'word': word,
            'videos_found': 0,
            'candidates_found': 0,
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

        # STAGE 2: Candidate selection with metadata transcript
        logger.info(f"  [Stage 2] Analyzing candidates with metadata transcripts...")
        candidate_videos = []
        for metadata in metadata_list:
            candidate_analysis = self.analyze_candidates(metadata, word, vocab_list)
            if candidate_analysis and candidate_analysis.get('mappings'):
                candidate_videos.append((metadata, candidate_analysis))

        word_stats['candidates_found'] = len(candidate_videos)
        logger.info(f"  [Stage 2] Found {len(candidate_videos)} candidate videos")

        if not candidate_videos:
            logger.info(f"  No quality candidates found for '{word}'")
            return word_stats

        # STAGE 3: Download videos, extract audio transcripts, and perform final analysis
        logger.info(f"  [Stage 3] Performing audio verification with Whisper...")
        for metadata, candidate_analysis in candidate_videos:
            slug = metadata.get('slug', '')

            # Skip if already uploaded or saved
            if slug in self.uploaded_videos or slug in self.saved_videos:
                status = "saved" if slug in self.saved_videos else "uploaded"
                logger.info(f"    Skipping {slug} - already {status}")
                continue

            # Download video
            video_path = self.download_video(metadata)
            if not video_path:
                continue

            # Extract audio transcript with Whisper
            audio_transcript = self.extract_audio_transcript(video_path, slug)
            if not audio_transcript:
                logger.warning(f"      Failed to extract audio transcript for {slug}")
                continue

            # Perform final analysis with audio transcript
            final_analysis = self.analyze_final(metadata, audio_transcript, word, vocab_list)
            if not final_analysis or not final_analysis.get('mappings'):
                logger.info(f"      No verified mappings for {slug} after audio analysis")
                continue

            word_stats['audio_verified'] += 1

            # Save to directory or upload to backend
            if self.download_only:
                # Download-only mode: save to directory structure
                save_result = self.save_video_to_directory(metadata, final_analysis, video_path, audio_transcript)
                if save_result:
                    word_stats['videos_uploaded'].append({
                        'slug': slug,
                        'mp3_path': save_result.get('mp3_path'),
                        'metadata_path': save_result.get('metadata_path'),
                        'status': 'saved',
                        'audio_verified': True
                    })
                    word_stats['mappings_created'].extend([
                        {'word': m['word'], 'edu_score': m['education_score'], 'ctx_score': m['context_score'], 'source': 'audio'}
                        for m in final_analysis['mappings']
                    ])
            else:
                # Upload to backend with audio transcript
                upload_result = self.upload_to_backend(metadata, final_analysis, video_path, audio_transcript)
                if upload_result:
                    word_stats['videos_uploaded'].append({
                        'slug': slug,
                        'video_id': upload_result.get('video_id'),
                        'status': upload_result.get('status'),
                        'audio_verified': True
                    })
                    word_stats['mappings_created'].extend([
                        {'word': m['word'], 'edu_score': m['education_score'], 'ctx_score': m['context_score'], 'source': 'audio'}
                        for m in final_analysis['mappings']
                    ])

        # Print word summary
        logger.info(f"\n{'='*60}")
        logger.info(f"SUMMARY FOR '{word.upper()}'")
        logger.info(f"{'='*60}")
        logger.info(f"Stage 1 - Videos found: {word_stats['videos_found']}")
        logger.info(f"Stage 2 - Candidates selected: {word_stats['candidates_found']}")
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
                logger.info(f"  - {m['word']} (edu={m['edu_score']:.2f}, ctx={m['ctx_score']:.2f}, source={m['source']})")

        logger.info(f"{'='*60}\n")

        return word_stats

    def run(self, words: Optional[List[str]] = None, source_name: Optional[str] = None):
        """Run the complete pipeline

        Args:
            words: Optional list of words to process (if None, loads from file)
            source_name: Optional source name for logging (bundle name or CSV path)
        """
        logger.info(f"\n{'='*80}")
        logger.info(f"STARTING VIDEO DISCOVERY PIPELINE")
        logger.info(f"{'='*80}")
        logger.info(f"Mode: {'DOWNLOAD-ONLY' if self.download_only else 'DOWNLOAD + UPLOAD'}")
        logger.info(f"Source ID: {self.source_id}")
        logger.info(f"Storage Dir: {self.storage_dir}")
        if self.download_only:
            logger.info(f"Output Dir: {self.output_dir}")
        else:
            logger.info(f"Backend URL: {self.backend_url}")
        logger.info(f"Word Source: {source_name or self.word_list_path}")
        logger.info(f"Max Videos per Word: {self.max_videos_per_word}")
        logger.info(f"Min Education Score: {self.education_min_score}")
        logger.info(f"Min Context Score: {self.context_min_score}")
        logger.info(f"{'='*80}\n")

        # Load words if not provided
        if words is None:
            words = self.load_words()
        vocab_list = words  # Full vocab list for LLM analysis

        # Process each word
        start_time = time.time()
        words_processed = 0
        all_word_stats = []

        for i, word in enumerate(words, 1):
            if word in self.processed_words:
                logger.info(f"\nSkipping '{word}' - already processed ({i}/{len(words)})")
                continue

            word_stats = self.process_word(word, vocab_list)
            all_word_stats.append(word_stats)
            self._save_processed_word(word)
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
        logger.info(f"Failed Uploads: {len(self.failed_uploads)}")
        logger.info(f"Time Elapsed: {elapsed/3600:.2f} hours")
        logger.info(f"{'='*80}")


def main():
    parser = argparse.ArgumentParser(
        description='Find videos for vocabulary words and upload to backend',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    # Word source: either CSV file or bundle name (mutually exclusive)
    word_source = parser.add_mutually_exclusive_group(required=True)
    word_source.add_argument(
        '--csv',
        help='Path to CSV file with word list'
    )
    word_source.add_argument(
        '--bundle',
        help='Bundle name to fetch words from (e.g., toefl_beginner, ielts_advanced)'
    )

    parser.add_argument(
        '--storage-dir',
        default='/Volumes/databank/dogetionary-pipeline',
        help='Base directory for caching (default: /Volumes/databank/dogetionary-pipeline)'
    )

    parser.add_argument(
        '--backend-url',
        default='http://localhost:5001',
        help='Backend API URL (default: http://localhost:5001)'
    )

    parser.add_argument(
        '--max-videos',
        type=int,
        default=100,
        help='Max videos to fetch per word (default: 100)'
    )

    parser.add_argument(
        '--education-min-score',
        type=float,
        default=0.6,
        help='Minimum education score - how well video illustrates word meaning (default: 0.6)'
    )

    parser.add_argument(
        '--context-min-score',
        type=float,
        default=0.6,
        help='Minimum context score - how well scene stands alone (default: 0.6)'
    )

    parser.add_argument(
        '--download-only',
        action='store_true',
        help='Download and process videos without uploading (saves to output directory)'
    )

    parser.add_argument(
        '--output-dir',
        help='Output directory for download-only mode (default: <storage-dir>/output)'
    )

    args = parser.parse_args()

    # Load secrets from .env.secrets
    env_path = Path(__file__).parent.parent / 'src' / '.env.secrets'
    if env_path.exists():
        load_dotenv(env_path)
        logger.info(f"Loaded secrets from {env_path}")
    else:
        logger.warning(f"Secrets file not found: {env_path}")

    clipcafe_api_key = os.getenv('CLIPCAFE')
    openai_api_key = os.getenv('OPENAI_API_KEY')

    if not clipcafe_api_key or not openai_api_key:
        logger.error("Missing API keys in .env.secrets (CLIPCAFE, OPENAI_API_KEY)")
        sys.exit(1)

    # Create pipeline
    finder = VideoFinder(
        storage_dir=args.storage_dir,
        backend_url=args.backend_url,
        word_list_path=args.csv if args.csv else None,
        clipcafe_api_key=clipcafe_api_key,
        openai_api_key=openai_api_key,
        max_videos_per_word=args.max_videos,
        education_min_score=args.education_min_score,
        context_min_score=args.context_min_score,
        download_only=args.download_only,
        output_dir=args.output_dir
    )

    # Get words from either bundle or CSV
    if args.bundle:
        words = finder.fetch_bundle_words(args.bundle)
    else:
        words = finder.load_words()

    # Run pipeline with words
    finder.run(words=words, source_name=args.bundle or args.csv)


if __name__ == '__main__':
    main()
