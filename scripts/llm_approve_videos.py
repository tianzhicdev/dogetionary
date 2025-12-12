#!/usr/bin/env python3
"""
llm_approve_videos.py - LLM-based video quality assessment for vocabulary learning

Evaluates videos using OpenAI LLM to determine if they:
1. Effectively illustrate vocabulary usage (educational_value_score >= 0.9)
2. Provide sufficient context to understand the scene (contextual_sufficiency_score >= 0.9)

Approved videos are moved to /Volumes/databank/llm_approved_videos/ with metadata_v3.json

Usage:
  python llm_approve_videos.py --max-videos 10  # Test on 10 videos
  python llm_approve_videos.py                  # Process all videos
"""

import os
import sys
import json
import shutil
import logging
import argparse
import subprocess
import requests
from pathlib import Path
from typing import Dict, Optional
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


class VideoQualityAssessor:
    """LLM-based video quality assessment for vocabulary learning"""

    def __init__(self, input_dir: str, output_dir: str, openai_api_key: str, model_name: str = None):
        self.input_dir = Path(input_dir)
        self.output_dir = Path(output_dir)
        self.openai_api_key = openai_api_key
        self.model_name = model_name or "gpt-4o-2024-08-06"

        # Statistics
        self.stats = {
            'total_videos': 0,
            'processed': 0,
            'approved': 0,
            'rejected': 0,
            'errors': 0,
            'whisper_api_calls': 0,
            'llm_api_calls': 0,
            'mp3_extracted': 0,
            'transcript_cached': 0
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

    def move_approved_video(self, source_folder: Path, metadata_v3: Dict):
        """Move entire video folder to approved directory"""
        video_name = source_folder.name
        dest_folder = self.output_dir / video_name

        try:
            # Create destination folder
            dest_folder.mkdir(parents=True, exist_ok=True)

            # Move all files
            for file in source_folder.glob('*'):
                dest_path = dest_folder / file.name
                shutil.move(str(file), str(dest_path))

            # Write metadata_v3.json
            v3_path = dest_folder / f"{video_name}.metadata_v3.json"
            with open(v3_path, 'w') as f:
                json.dump(metadata_v3, f, indent=2)

            # Remove empty source folder
            source_folder.rmdir()

            logger.info(f"    ✓ Moved to {dest_folder.name}/")
            self.stats['approved'] += 1

        except Exception as e:
            logger.error(f"    ✗ Failed to move folder: {e}")
            self.stats['errors'] += 1

    def process_video(self, video_folder: Path) -> bool:
        """Process a single video folder"""
        video_name = video_folder.name
        logger.info(f"\n[{self.stats['processed'] + 1}] Processing: {video_name}")

        try:
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

            # 4. If approved, move to approved directory
            if assessment['overall_approved']:
                metadata_v3 = self.build_metadata_v3(
                    original_metadata,
                    transcript_data,
                    assessment
                )
                self.move_approved_video(video_folder, metadata_v3)
                logger.info(f"    ✅ APPROVED")
            else:
                logger.info(f"    ❌ REJECTED: {assessment.get('rejection_reason', 'Did not meet threshold')}")
                self.stats['rejected'] += 1

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
        logger.info(f"LLM VIDEO QUALITY ASSESSMENT")
        logger.info(f"{'='*80}")
        logger.info(f"Input: {self.input_dir}")
        logger.info(f"Output: {self.output_dir}")
        logger.info(f"Model: {self.model_name}")
        logger.info(f"Max videos: {max_videos or 'All'}")
        logger.info(f"{'='*80}\n")

        # Create output directory
        self.output_dir.mkdir(parents=True, exist_ok=True)

        # Get all video folders
        video_folders = [d for d in self.input_dir.iterdir() if d.is_dir()]
        self.stats['total_videos'] = len(video_folders)

        if max_videos:
            video_folders = sorted(video_folders)[:max_videos]

        logger.info(f"Found {len(video_folders)} videos to process\n")

        # Process each video
        for video_folder in video_folders:
            self.process_video(video_folder)

            # Progress update
            if self.stats['processed'] > 0 and self.stats['processed'] % 10 == 0:
                logger.info(f"\n--- Progress: {self.stats['processed']} processed, "
                           f"{self.stats['approved']} approved, "
                           f"{self.stats['rejected']} rejected ---\n")

        # Summary
        end_time = datetime.now()
        duration = end_time - start_time

        logger.info(f"\n{'='*80}")
        logger.info(f"SUMMARY")
        logger.info(f"{'='*80}")
        logger.info(f"Total videos: {self.stats['total_videos']}")
        logger.info(f"Processed: {self.stats['processed']}")
        logger.info(f"Approved: {self.stats['approved']} ({self.stats['approved']/max(self.stats['processed'],1)*100:.1f}%)")
        logger.info(f"Rejected: {self.stats['rejected']} ({self.stats['rejected']/max(self.stats['processed'],1)*100:.1f}%)")
        logger.info(f"Errors: {self.stats['errors']}")
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
        description='LLM-based video quality assessment for vocabulary learning',
        formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument(
        '--input-dir',
        default='/Volumes/databank/shortfilms',
        help='Input directory with video folders (default: /Volumes/databank/shortfilms)'
    )

    parser.add_argument(
        '--output-dir',
        default='/Volumes/databank/llm_approved_videos',
        help='Output directory for approved videos (default: /Volumes/databank/llm_approved_videos)'
    )

    parser.add_argument(
        '--max-videos',
        type=int,
        help='Maximum number of videos to process (for testing)'
    )

    parser.add_argument(
        '--model',
        default=None,
        help='OpenAI model to use (default: from config)'
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

    # Create assessor and run
    assessor = VideoQualityAssessor(
        input_dir=args.input_dir,
        output_dir=args.output_dir,
        openai_api_key=openai_api_key,
        model_name=args.model
    )

    assessor.run(max_videos=args.max_videos)


if __name__ == '__main__':
    main()
