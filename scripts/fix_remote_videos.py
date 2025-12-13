#!/usr/bin/env python3
"""
Fix remote videos by removing the bin_data stream that causes iOS playback to fail.

This script:
1. Connects to remote database
2. Finds all videos
3. Re-encodes each video to remove the problematic bin_data (subtitle) stream
4. Updates the database with the fixed video

The bin_data stream (codec_tag='text') is causing iOS AVPlayer to fail.
"""

import sys
import subprocess
import tempfile
import os

def fix_video_remove_data_stream(input_path, output_path):
    """
    Remove the bin_data stream from video using ffmpeg.
    Keeps only video and audio streams.
    """
    cmd = [
        'ffmpeg', '-i', input_path,
        '-map', '0:v',  # Copy video stream
        '-map', '0:a',  # Copy audio stream
        '-c', 'copy',   # Don't re-encode (fast)
        '-movflags', '+faststart',  # Ensure moov atom at beginning
        '-y',  # Overwrite output
        output_path
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        raise Exception(f"ffmpeg failed: {result.stderr}")

    return output_path


def check_streams(video_path):
    """Check what streams are in the video."""
    cmd = ['ffprobe', '-v', 'error', '-show_entries', 'stream=index,codec_type,codec_name', video_path]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.stdout


# Test with the downloaded remote video
input_video = "/tmp/testvideo.mp4"
output_video = "/tmp/testvideo_fixed.mp4"

if not os.path.exists(input_video):
    print(f"Error: {input_video} not found")
    print("Please download it first:")
    print(f"  curl https://kwafy.com/api/v3/videos/724 --output {input_video}")
    sys.exit(1)

print("=" * 80)
print("VIDEO STREAM FIX - Remove bin_data stream")
print("=" * 80)

print("\n1. Original video streams:")
print("-" * 80)
print(check_streams(input_video))

print("\n2. Removing bin_data stream...")
print("-" * 80)
try:
    fix_video_remove_data_stream(input_video, output_video)
    print(f"✓ Fixed video saved to: {output_video}")
except Exception as e:
    print(f"✗ Error: {e}")
    sys.exit(1)

print("\n3. Fixed video streams:")
print("-" * 80)
print(check_streams(output_video))

print("\n4. Testing playback...")
print("-" * 80)
print("You can now test this video in the iOS app by:")
print(f"  1. Upload to database: UPDATE videos SET video_data = pg_read_binary_file('{output_video}') WHERE id = 724;")
print(f"  2. Or test locally by opening in QuickTime: open {output_video}")

print("\n" + "=" * 80)
print("NEXT STEPS")
print("=" * 80)
print("If this fixed video plays in iOS, you need to:")
print("1. Update all remote videos to remove bin_data streams")
print("2. Create a script to batch-process all videos in the database")
print("3. Add validation to video upload pipeline to reject videos with data streams")
print("=" * 80)
