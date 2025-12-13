#!/usr/bin/env python3
"""
Test the video processing logic from upload_from_catalog.py
"""

import subprocess
import tempfile
import os

def process_video(input_path: str) -> bytes:
    """
    Process video to remove data streams (subtitles/text) that break iOS playback
    Returns the processed video bytes
    """
    # Create temporary file for processed video
    with tempfile.NamedTemporaryFile(suffix='.mp4', delete=False) as tmp:
        tmp_path = tmp.name

    try:
        # Strip data streams using ffmpeg
        cmd = [
            'ffmpeg', '-i', str(input_path),
            '-map', '0:v',  # Copy video
            '-map', '0:a',  # Copy audio
            '-c', 'copy',   # Don't re-encode
            '-movflags', '+faststart',  # iOS optimization
            '-y',  # Overwrite
            tmp_path
        ]

        print(f"Running: {' '.join(cmd)}")
        result = subprocess.run(cmd, capture_output=True)

        if result.returncode == 0:
            # Successfully processed - read cleaned video
            with open(tmp_path, 'rb') as f:
                mp4_bytes = f.read()
            print(f"✓ Successfully processed video")
            print(f"  Input size: {os.path.getsize(input_path) / 1024:.1f} KB")
            print(f"  Output size: {len(mp4_bytes) / 1024:.1f} KB")
            return mp4_bytes
        else:
            print(f"✗ Failed to process video")
            print(f"  Return code: {result.returncode}")
            print(f"  stderr: {result.stderr.decode()[:500]}")

            # Fallback to original if processing fails
            print(f"  Using original video as fallback")
            with open(input_path, 'rb') as f:
                return f.read()
    finally:
        # Clean up temp file
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)


# Test with the remote video we downloaded
test_video = "/tmp/testvideo.mp4"

if not os.path.exists(test_video):
    print(f"Error: {test_video} not found")
    print("Download it first:")
    print(f"  curl https://kwafy.com/api/v3/videos/724 --output {test_video}")
    exit(1)

print("=" * 80)
print("Testing Video Processing")
print("=" * 80)

print("\n1. Original video streams:")
result = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'stream=codec_type', test_video],
                       capture_output=True, text=True)
print(result.stdout)

print("\n2. Processing video...")
processed_bytes = process_video(test_video)

print("\n3. Saving processed video...")
output_path = "/tmp/testvideo_processed.mp4"
with open(output_path, 'wb') as f:
    f.write(processed_bytes)
print(f"Saved to: {output_path}")

print("\n4. Processed video streams:")
result = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'stream=codec_type', output_path],
                       capture_output=True, text=True)
print(result.stdout)

print("\n" + "=" * 80)
print("Test Complete")
print("=" * 80)
print(f"If the processed video only has 'video' and 'audio' streams (no 'data'),")
print(f"then the fix works correctly!")
print("=" * 80)
