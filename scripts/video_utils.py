#!/usr/bin/env python3
"""
Video utility functions for metadata extraction and processing.
Uses ffprobe (part of ffmpeg) to extract video metadata.
"""

import json
import subprocess
import os
from pathlib import Path
from typing import Dict, Optional, Tuple


def check_ffprobe_installed() -> bool:
    """
    Check if ffprobe is installed and available.

    Returns:
        bool: True if ffprobe is available, False otherwise
    """
    try:
        subprocess.run(['ffprobe', '-version'],
                      capture_output=True,
                      check=True)
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False


def extract_video_metadata(video_path: str) -> Dict:
    """
    Extract metadata from a video file using ffprobe.

    Args:
        video_path: Path to the video file

    Returns:
        dict: Video metadata including duration, resolution, codec, bitrate, fps, etc.

    Raises:
        FileNotFoundError: If video file doesn't exist
        RuntimeError: If ffprobe is not installed or fails
    """
    if not os.path.exists(video_path):
        raise FileNotFoundError(f"Video file not found: {video_path}")

    if not check_ffprobe_installed():
        raise RuntimeError("ffprobe is not installed. Install ffmpeg to use this feature.")

    # Run ffprobe to extract metadata
    cmd = [
        'ffprobe',
        '-v', 'quiet',
        '-print_format', 'json',
        '-show_format',
        '-show_streams',
        video_path
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, check=True, text=True)
        probe_data = json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        raise RuntimeError(f"ffprobe failed: {e.stderr}")
    except json.JSONDecodeError as e:
        raise RuntimeError(f"Failed to parse ffprobe output: {e}")

    # Extract relevant information
    metadata = {}

    # Get format information
    if 'format' in probe_data:
        format_info = probe_data['format']
        metadata['file_size_bytes'] = int(format_info.get('size', 0))
        metadata['duration_seconds'] = float(format_info.get('duration', 0))
        metadata['bitrate'] = int(format_info.get('bit_rate', 0))
        metadata['format_name'] = format_info.get('format_name', '')

    # Get video stream information
    video_stream = None
    if 'streams' in probe_data:
        for stream in probe_data['streams']:
            if stream.get('codec_type') == 'video':
                video_stream = stream
                break

    if video_stream:
        metadata['codec'] = video_stream.get('codec_name', '')
        metadata['resolution'] = f"{video_stream.get('width', 0)}x{video_stream.get('height', 0)}"

        # Calculate FPS from avg_frame_rate (format: "30000/1001")
        fps_str = video_stream.get('avg_frame_rate', '0/1')
        if '/' in fps_str:
            num, den = map(int, fps_str.split('/'))
            metadata['fps'] = round(num / den, 2) if den != 0 else 0
        else:
            metadata['fps'] = 0

    return metadata


def parse_video_filename(filename: str) -> Tuple[str, Optional[str], str]:
    """
    Parse video filename to extract name, language, and format.

    Expected formats:
        - "hello.mp4" -> ("hello", None, "mp4")
        - "hello_en.mp4" -> ("hello", "en", "mp4")
        - "good_morning_zh.mov" -> ("good_morning", "zh", "mov")

    Args:
        filename: Video filename (with or without path)

    Returns:
        tuple: (name, language, format)
    """
    # Get just the filename without path
    base_filename = os.path.basename(filename)

    # Split extension
    name_part, ext = os.path.splitext(base_filename)
    format_type = ext.lstrip('.').lower()

    # Check if language code is at the end (e.g., "hello_en")
    parts = name_part.rsplit('_', 1)
    if len(parts) == 2 and len(parts[1]) == 2 and parts[1].isalpha():
        # Likely a language code
        name = parts[0]
        language = parts[1].lower()
    else:
        name = name_part
        language = None

    return name, language, format_type


def load_transcript(video_path: str) -> Optional[str]:
    """
    Load transcript file for a video if it exists.

    Looks for a .txt file or .json file with the same name as the video.
    Example: "hello.mp4" -> "hello.txt" or "hello.json"

    Args:
        video_path: Path to the video file

    Returns:
        str: Transcript content, or None if no transcript file exists
    """
    # Try .txt file first
    transcript_path = Path(video_path).with_suffix('.txt')

    if transcript_path.exists():
        try:
            with open(transcript_path, 'r', encoding='utf-8') as f:
                return f.read().strip()
        except Exception as e:
            print(f"Warning: Failed to read transcript {transcript_path}: {e}")

    # Try .json file
    json_path = Path(video_path).with_suffix('.json')

    if json_path.exists():
        try:
            with open(json_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
                # Check for transcript field
                if 'transcript' in data and data['transcript']:
                    return data['transcript'].strip()
        except Exception as e:
            print(f"Warning: Failed to read JSON {json_path}: {e}")

    return None


def load_json_metadata(video_path: str) -> Optional[Dict]:
    """
    Load JSON metadata file if it exists.

    Args:
        video_path: Path to the video file

    Returns:
        dict: JSON metadata or None if not found
    """
    json_path = Path(video_path).with_suffix('.json')

    if json_path.exists():
        try:
            with open(json_path, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception as e:
            print(f"Warning: Failed to read JSON {json_path}: {e}")

    return None


def get_video_info(video_path: str) -> Dict:
    """
    Get complete video information including metadata, filename parsing, and transcript.

    Args:
        video_path: Path to the video file

    Returns:
        dict: Complete video information ready for database insertion
    """
    # Parse filename
    name, language, format_type = parse_video_filename(video_path)

    # Extract metadata from video file
    metadata = extract_video_metadata(video_path)

    # Load JSON metadata if available
    json_metadata = load_json_metadata(video_path)

    # Add parsed information to metadata
    if language:
        metadata['language'] = language

    # Store vocabulary_word in metadata (don't use it as the name - name should be unique per video)
    if json_metadata and 'vocabulary_word' in json_metadata:
        metadata['word'] = json_metadata['vocabulary_word']
    else:
        metadata['word'] = name.replace('_', ' ')  # Convert underscores to spaces for multi-word phrases

    # Merge additional JSON metadata (excluding binary/large fields)
    if json_metadata:
        # Add selected fields from JSON metadata
        for key in ['clip_title', 'clip_slug', 'movie_title', 'movie_year', 'imdb_id', 'movie_plot']:
            if key in json_metadata and json_metadata[key]:
                metadata[key] = json_metadata[key]

    # Load transcript
    transcript = load_transcript(video_path)

    # Read video binary data
    with open(video_path, 'rb') as f:
        video_data = f.read()

    return {
        'name': name,
        'format': format_type,
        'video_data': video_data,
        'transcript': transcript,
        'metadata': metadata
    }


def format_file_size(size_bytes: int) -> str:
    """
    Format file size in human-readable format.

    Args:
        size_bytes: File size in bytes

    Returns:
        str: Formatted size (e.g., "1.5 MB", "523 KB")
    """
    for unit in ['B', 'KB', 'MB', 'GB']:
        if size_bytes < 1024:
            return f"{size_bytes:.1f} {unit}"
        size_bytes /= 1024
    return f"{size_bytes:.1f} TB"


def format_duration(seconds: float) -> str:
    """
    Format duration in human-readable format.

    Args:
        seconds: Duration in seconds

    Returns:
        str: Formatted duration (e.g., "5.2s", "1m 30s", "1h 15m 30s")
    """
    if seconds < 60:
        return f"{seconds:.1f}s"

    minutes = int(seconds // 60)
    remaining_seconds = int(seconds % 60)

    if minutes < 60:
        return f"{minutes}m {remaining_seconds}s"

    hours = minutes // 60
    remaining_minutes = minutes % 60
    return f"{hours}h {remaining_minutes}m {remaining_seconds}s"


if __name__ == '__main__':
    # Quick test if run directly
    import sys

    if len(sys.argv) < 2:
        print("Usage: python video_utils.py <video_file>")
        sys.exit(1)

    video_path = sys.argv[1]

    if not check_ffprobe_installed():
        print("Error: ffprobe is not installed.")
        print("Install ffmpeg: brew install ffmpeg")
        sys.exit(1)

    print(f"Analyzing: {video_path}")
    print("-" * 60)

    info = get_video_info(video_path)

    print(f"Name: {info['name']}")
    print(f"Format: {info['format']}")
    print(f"Video size: {format_file_size(len(info['video_data']))}")
    print(f"Transcript: {info['transcript'] or 'None'}")
    print(f"\nMetadata:")
    for key, value in info['metadata'].items():
        if key == 'file_size_bytes':
            print(f"  {key}: {format_file_size(value)}")
        elif key == 'duration_seconds':
            print(f"  {key}: {format_duration(value)}")
        else:
            print(f"  {key}: {value}")
