#!/usr/bin/env python3
"""
videos_eval_v3.py - Generate v3.json with LLM quality assessment and maintain catalog.csv

Evaluates videos using OpenAI LLM and:
1. Creates <videoname>.v3.json in place with quality scores
2. Appends to /Volumes/databank/shortfilms/catalog.csv with all video metadata
3. Fully idempotent (skips if v3.json already exists)

Usage:
  python videos_eval_v3.py --max-videos 10  # Test on 10 videos
  python videos_eval_v3.py                  # Process all videos
"""

import os
import sys
import json
import csv
import logging
import argparse
import subprocess
import requests
from pathlib import Path
from typing import Dict, Optional, List
from datetime import datetime
from dotenv import load_dotenv

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

# Direct OpenAI API implementation (no dependencies)
def llm_completion(messages, response_format=None, model="gpt-4o-2024-08-06", api_key=None):
    """Direct OpenAI API call"""
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }

    data = {
        "model": model,
        "messages": messages
    }

    if response_format:
        data["response_format"] = response_format

    response = requests.post(
        "https://api.openai.com/v1/chat/completions",
        headers=headers,
        json=data,
        timeout=60
    )
    response.raise_for_status()
    return response.json()


# LLM Quality Assessment Schema
QUALITY_ASSESSMENT_SCHEMA = {
    "type": "object",
    "properties": {
        "educational_value_score": {
            "type": "number",
            "description": "Score 0-1 for how well this illustrates vocabulary usage"
        },
        "contextual_sufficiency_score": {
            "type": "number",
            "description": "Score 0-1 for how well the scene provides sufficient context"
        },
        "overall_approved": {
            "type": "boolean",
            "description": "True if BOTH scores >= 0.9"
        },
        "illustrated_words": {
            "type": "array",
            "items": {"type": "string"},
            "description": "List of vocabulary words this video effectively illustrates (3-10 words)"
        },
        "rejection_reason": {
            "type": ["string", "null"],
            "description": "If rejected, brief explanation of why"
        },
        "educational_notes": {
            "type": ["string", "null"],
            "description": "Optional: What makes this clip educational (or not)"
        },
        "contextual_notes": {
            "type": ["string", "null"],
            "description": "Optional: What context is provided (or missing)"
        },
        "difficulty_level": {
            "type": "string",
            "enum": ["beginner", "intermediate", "advanced"],
            "description": "Estimated difficulty level for English learners"
        }
    },
    "required": [
        "educational_value_score",
        "contextual_sufficiency_score",
        "overall_approved",
        "illustrated_words",
        "rejection_reason",
        "educational_notes",
        "contextual_notes",
        "difficulty_level"
    ],
    "additionalProperties": False
}


class VideoEvaluatorV3:
    """Generate v3.json with LLM quality assessment and maintain catalog.csv"""

    def __init__(self, input_dir: str, catalog_path: str, openai_api_key: str, model_name: str = None):
        self.input_dir = Path(input_dir)
        self.catalog_path = Path(catalog_path)
        self.openai_api_key = openai_api_key
        self.model_name = model_name or "gpt-4o-2024-08-06"

        # Statistics
        self.stats = {
            'total_videos': 0,
            'processed': 0,
            'skipped_v3_exists': 0,
            'errors': 0,
            'whisper_api_calls': 0,
            'llm_api_calls': 0,
            'mp3_extracted': 0,
            'transcript_cached': 0,
            'v3_created': 0,
            'catalog_entries': 0
        }

    def extract_mp3(self, mp4_path: Path) -> Optional[Path]:
        """Extract MP3 from MP4 using ffmpeg"""
        mp3_path = mp4_path.with_suffix('.mp3')

        if mp3_path.exists():
            return mp3_path

        try:
            logger.info(f"    Extracting MP3 from {mp4_path.name}...")
            result = subprocess.run([
                'ffmpeg',
                '-i', str(mp4_path),
                '-vn',
                '-acodec', 'libmp3lame',
                '-q:a', '2',
                '-y',
                str(mp3_path)
            ], check=True, capture_output=True, text=True)

            self.stats['mp3_extracted'] += 1
            logger.info(f"    ✓ Extracted MP3")
            return mp3_path

        except subprocess.CalledProcessError as e:
            logger.error(f"    ✗ ffmpeg failed: {e.stderr[:200]}")
            return None
        except Exception as e:
            logger.error(f"    ✗ Failed to extract MP3: {e}")
            return None

    def get_whisper_transcript(self, mp3_path: Path) -> Optional[Dict]:
        """Get audio transcript using OpenAI Whisper API"""
        try:
            logger.info(f"    Calling Whisper API...")

            with open(mp3_path, 'rb') as audio_file:
                response = requests.post(
                    'https://api.openai.com/v1/audio/transcriptions',
                    headers={'Authorization': f'Bearer {self.openai_api_key}'},
                    files={'file': audio_file},
                    data={
                        'model': 'whisper-1',
                        'response_format': 'verbose_json'
                    },
                    timeout=60
                )
                response.raise_for_status()

            result = response.json()
            self.stats['whisper_api_calls'] += 1

            logger.info(f"    ✓ Whisper: {len(result.get('text', '').split())} words, {result.get('duration', 0):.1f}s")

            return {
                'text': result.get('text', '').strip(),
                'duration': result.get('duration', 0)
            }

        except Exception as e:
            logger.error(f"    ✗ Whisper failed: {e}")
            return None

    def get_audio_transcript(self, video_folder: Path) -> Optional[Dict]:
        """Get audio transcript (from v2.json cache or Whisper API)"""
        video_name = video_folder.name

        # Check v2.json first
        v2_json_path = video_folder / f"{video_name}.v2.json"
        if v2_json_path.exists():
            try:
                with open(v2_json_path, 'r') as f:
                    v2_data = json.load(f)

                if v2_data.get('audio_transcript'):
                    logger.info(f"    ✓ Using cached transcript from v2.json")
                    self.stats['transcript_cached'] += 1
                    return {
                        'text': v2_data['audio_transcript'],
                        'duration': v2_data.get('audio_duration', 0)
                    }
            except Exception as e:
                logger.warning(f"    Failed to read v2.json: {e}")

        # Try to get MP3
        mp3_path = video_folder / f"{video_name}.mp3"
        if not mp3_path.exists():
            # Try to extract from MP4
            mp4_path = video_folder / f"{video_name}.mp4"
            if mp4_path.exists():
                mp3_path = self.extract_mp3(mp4_path)

            if not mp3_path:
                logger.error(f"    ✗ No MP3 and couldn't extract from MP4")
                return None

        # Call Whisper API
        return self.get_whisper_transcript(mp3_path)

    def assess_video_quality(self, transcript: str, metadata: Dict) -> Optional[Dict]:
        """Call OpenAI LLM to assess video quality"""
        try:
            logger.info(f"    Calling LLM for quality assessment...")

            prompt = f"""You are an expert ESL teacher evaluating movie clips for vocabulary learning.

CLIP INFORMATION:
Movie: {metadata.get('movie_title', 'Unknown')}
Year: {metadata.get('movie_year', 'N/A')}
Plot: {metadata.get('movie_plot', 'N/A')}
Duration: {metadata.get('duration_seconds', 'N/A')} seconds
Transcript: "{transcript}"

EVALUATION CRITERIA (Be STRICT - only approve excellent clips):

1. EDUCATIONAL VALUE (Score 0.0-1.0):
   - Does this transcript clearly demonstrate how words are used in natural English?
   - Are words used in authentic, meaningful context?
   - Can learners understand word usage from this clip?
   - Are there multiple valuable vocabulary words illustrated?
   - Score >= 0.9 means: Perfect example of vocabulary in use

2. CONTEXTUAL SUFFICIENCY (Score 0.0-1.0):
   - Can someone understand this scene WITHOUT seeing the full movie?
   - Is there enough information in the transcript to build context?
   - Are the characters/situation/setting clear?
   - Does this clip make sense as a standalone piece?
   - Score >= 0.9 means: Scene is completely self-contained and clear

STRICT REQUIREMENTS:
- BOTH scores must be >= 0.9 for approval
- Be conservative - reject borderline cases
- Reject if transcript is too short (<5 words)
- Reject if context requires movie knowledge
- Reject if vocabulary usage is unclear

IDENTIFY WORDS:
- List 3-10 vocabulary words this clip effectively illustrates
- Only include words clearly demonstrated in the transcript
- Focus on intermediate-advanced vocabulary
- Exclude very common words (the, is, and, etc.)

Provide your assessment in the structured format."""

            response = llm_completion(
                messages=[
                    {
                        "role": "system",
                        "content": "You are a strict ESL content curator evaluating movie clips for vocabulary learning. Only approve clips that are exceptional for teaching vocabulary."
                    },
                    {
                        "role": "user",
                        "content": prompt
                    }
                ],
                model=self.model_name,
                api_key=self.openai_api_key,
                response_format={
                    "type": "json_schema",
                    "json_schema": {
                        "name": "video_quality_assessment",
                        "strict": True,
                        "schema": QUALITY_ASSESSMENT_SCHEMA
                    }
                }
            )

            self.stats['llm_api_calls'] += 1
            result = response['choices'][0]['message']['content']
            assessment = json.loads(result)

            logger.info(f"    ✓ LLM Assessment:")
            logger.info(f"      Educational: {assessment['educational_value_score']:.2f}")
            logger.info(f"      Context: {assessment['contextual_sufficiency_score']:.2f}")
            logger.info(f"      Approved: {assessment['overall_approved']}")
            logger.info(f"      Words: {', '.join(assessment['illustrated_words'][:5])}")

            return assessment

        except requests.exceptions.HTTPError as e:
            logger.error(f"    ✗ LLM API error: {e}")
            if hasattr(e.response, 'text'):
                logger.error(f"    Response: {e.response.text[:300]}")
            return None
        except Exception as e:
            logger.error(f"    ✗ LLM assessment failed: {e}")
            return None

    def build_metadata_v3(self, original_json: Dict, transcript_data: Dict, assessment: Dict) -> Dict:
        """Build metadata_v3.json with LLM assessment"""
        metadata_v3 = {
            # Original metadata
            "video_name": original_json.get('clip_slug', ''),
            "movie_title": original_json.get('movie_title'),
            "movie_year": original_json.get('movie_year'),
            "movie_plot": original_json.get('movie_plot'),
            "imdb_id": original_json.get('imdb_id'),
            "clip_id": original_json.get('clip_id'),
            "duration_seconds": original_json.get('duration_seconds'),

            # Audio transcript
            "audio_transcript": transcript_data['text'],
            "audio_duration": transcript_data['duration'],
            "audio_transcript_verified": True,

            # LLM Quality Assessment
            "llm_assessment": {
                "educational_value_score": assessment['educational_value_score'],
                "contextual_sufficiency_score": assessment['contextual_sufficiency_score'],
                "overall_approved": assessment['overall_approved'],
                "illustrated_words": assessment['illustrated_words'],
                "difficulty_level": assessment['difficulty_level'],
                "educational_notes": assessment.get('educational_notes'),
                "contextual_notes": assessment.get('contextual_notes'),
                "rejection_reason": assessment.get('rejection_reason'),
                "assessed_at": datetime.now().isoformat(),
                "model_used": self.model_name
            },

            # Processing metadata
            "metadata_version": 3,
            "processed_at": datetime.now().isoformat(),
            "source": "llm_approve_videos"
        }

        return metadata_v3

    def write_v3_and_catalog(self, video_folder: Path, metadata_v3: Dict):
        """Write v3.json in place and append to catalog.csv"""
        video_name = video_folder.name

        try:
            # 1. Write <videoname>.v3.json in place
            v3_path = video_folder / f"{video_name}.v3.json"
            with open(v3_path, 'w') as f:
                json.dump(metadata_v3, f, indent=2)

            self.stats['v3_created'] += 1
            logger.info(f"    ✓ Created {video_name}.v3.json")

            # 2. Append to catalog.csv
            assessment = metadata_v3['llm_assessment']
            linked_words = ','.join(assessment['illustrated_words'])

            # Ensure catalog.csv has headers if it doesn't exist
            catalog_exists = self.catalog_path.exists()

            with open(self.catalog_path, 'a', newline='', encoding='utf-8') as csvfile:
                writer = csv.writer(csvfile)

                # Write header if new file
                if not catalog_exists:
                    writer.writerow([
                        'video_name',
                        'educational_score',
                        'context_score',
                        'audio_transcript',
                        'linked_words'
                    ])

                # Write row
                writer.writerow([
                    video_name,
                    f"{assessment['educational_value_score']:.2f}",
                    f"{assessment['contextual_sufficiency_score']:.2f}",
                    metadata_v3['audio_transcript'],
                    linked_words
                ])

            self.stats['catalog_entries'] += 1
            logger.info(f"    ✓ Appended to catalog.csv")

        except Exception as e:
            logger.error(f"    ✗ Failed to write v3 and catalog: {e}")
            self.stats['errors'] += 1

    def process_video(self, video_folder: Path) -> bool:
        """Process a single video folder (idempotent - skips if v3.json exists)"""
        video_name = video_folder.name
        logger.info(f"\n[{self.stats['processed'] + 1}] Processing: {video_name}")

        try:
            # 0. IDEMPOTENCY CHECK: Skip if v3.json already exists
            v3_path = video_folder / f"{video_name}.v3.json"
            if v3_path.exists():
                logger.info(f"    ⏭️  Skipping (v3.json already exists)")
                self.stats['skipped_v3_exists'] += 1
                return True

            # 1. Load original metadata
            json_path = video_folder / f"{video_name}.json"
            if not json_path.exists():
                logger.warning(f"    ✗ No metadata JSON found")
                self.stats['errors'] += 1
                return False

            with open(json_path, 'r') as f:
                original_metadata = json.load(f)

            # 2. Get audio transcript
            transcript_data = self.get_audio_transcript(video_folder)
            if not transcript_data:
                logger.warning(f"    ✗ Failed to get transcript")
                self.stats['errors'] += 1
                return False

            # 3. Assess quality with LLM
            assessment = self.assess_video_quality(
                transcript_data['text'],
                original_metadata
            )
            if not assessment:
                logger.warning(f"    ✗ Failed to assess quality")
                self.stats['errors'] += 1
                return False

            # 4. Build metadata_v3 (for ALL videos, not just approved)
            metadata_v3 = self.build_metadata_v3(
                original_metadata,
                transcript_data,
                assessment
            )

            # 5. Write v3.json and append to catalog.csv
            self.write_v3_and_catalog(video_folder, metadata_v3)

            # Log result
            if assessment['overall_approved']:
                logger.info(f"    ✅ Quality: Educational={assessment['educational_value_score']:.2f}, Context={assessment['contextual_sufficiency_score']:.2f}")
            else:
                logger.info(f"    📊 Quality: Educational={assessment['educational_value_score']:.2f}, Context={assessment['contextual_sufficiency_score']:.2f}")

            self.stats['processed'] += 1
            return True

        except Exception as e:
            logger.error(f"    ✗ Error processing video: {e}")
            self.stats['errors'] += 1
            return False

    def run(self, max_videos: int = None):
        """Run quality assessment on all videos"""
        start_time = datetime.now()

        logger.info(f"\n{'='*80}")
        logger.info(f"VIDEO EVALUATION V3 - LLM QUALITY ASSESSMENT")
        logger.info(f"{'='*80}")
        logger.info(f"Input: {self.input_dir}")
        logger.info(f"Catalog: {self.catalog_path}")
        logger.info(f"Model: {self.model_name}")
        logger.info(f"Max videos: {max_videos or 'All'}")
        logger.info(f"{'='*80}\n")

        # Get all video folders
        video_folders = [d for d in self.input_dir.iterdir() if d.is_dir() and not d.name.startswith('.')]
        self.stats['total_videos'] = len(video_folders)

        if max_videos:
            video_folders = sorted(video_folders)[:max_videos]

        logger.info(f"Found {len(video_folders)} videos to process\n")

        # Process each video
        for video_folder in video_folders:
            self.process_video(video_folder)

            # Progress update
            total_count = self.stats['processed'] + self.stats['skipped_v3_exists']
            if total_count > 0 and total_count % 10 == 0:
                logger.info(f"\n--- Progress: {total_count} total, "
                           f"{self.stats['processed']} new, "
                           f"{self.stats['skipped_v3_exists']} skipped ---\n")

        # Summary
        end_time = datetime.now()
        duration = end_time - start_time

        logger.info(f"\n{'='*80}")
        logger.info(f"SUMMARY")
        logger.info(f"{'='*80}")
        logger.info(f"Total video folders: {self.stats['total_videos']}")
        logger.info(f"Processed (new v3.json): {self.stats['processed']}")
        logger.info(f"Skipped (v3.json exists): {self.stats['skipped_v3_exists']}")
        logger.info(f"Errors: {self.stats['errors']}")
        logger.info(f"")
        logger.info(f"Output:")
        logger.info(f"  v3.json files created: {self.stats['v3_created']}")
        logger.info(f"  Catalog entries added: {self.stats['catalog_entries']}")
        logger.info(f"")
        logger.info(f"Audio Processing:")
        logger.info(f"  Cached transcripts: {self.stats['transcript_cached']}")
        logger.info(f"  Whisper API calls: {self.stats['whisper_api_calls']}")
        logger.info(f"  MP3 extracted: {self.stats['mp3_extracted']}")
        logger.info(f"")
        logger.info(f"LLM Calls: {self.stats['llm_api_calls']}")
        logger.info(f"Duration: {duration}")
        logger.info(f"{'='*80}")


def main():
    parser = argparse.ArgumentParser(
        description='Generate v3.json with LLM quality assessment and maintain catalog.csv',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument(
        '--input-dir',
        default='/Volumes/databank/shortfilms',
        help='Input directory with video folders (default: /Volumes/databank/shortfilms)'
    )

    parser.add_argument(
        '--catalog',
        default='/Volumes/databank/shortfilms/catalog.csv',
        help='Catalog CSV file path (default: /Volumes/databank/shortfilms/catalog.csv)'
    )

    parser.add_argument(
        '--max-videos',
        type=int,
        help='Maximum number of videos to process (for testing)'
    )

    parser.add_argument(
        '--model',
        default=None,
        help='OpenAI model to use (default: gpt-4o-2024-08-06)'
    )

    args = parser.parse_args()

    # Load secrets
    env_path = Path(__file__).parent.parent / 'src' / '.env.secrets'
    if env_path.exists():
        load_dotenv(env_path)
        logger.info(f"Loaded secrets from {env_path}\n")
    else:
        logger.error(f"Secrets file not found: {env_path}")
        sys.exit(1)

    openai_api_key = os.getenv('OPENAI_API_KEY')
    if not openai_api_key:
        logger.error("Missing OPENAI_API_KEY in .env.secrets")
        sys.exit(1)

    # Create evaluator and run
    evaluator = VideoEvaluatorV3(
        input_dir=args.input_dir,
        catalog_path=args.catalog,
        openai_api_key=openai_api_key,
        model_name=args.model
    )

    evaluator.run(max_videos=args.max_videos)


if __name__ == '__main__':
    main()
