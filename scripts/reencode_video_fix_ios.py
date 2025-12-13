#!/usr/bin/env python3
"""
Re-encode video to remove bin_data stream (requires full re-encode, not just copy)
This is the ONLY way to remove the embedded data stream.
"""

import subprocess
import sys
import os

def reencode_video_for_ios(input_path: str, output_path: str):
    """
    Re-encode video to strip bin_data stream and optimize for iOS.
    This does a full re-encode which takes time but removes all unwanted streams.
    """
    cmd = [
        'ffmpeg', '-i', input_path,
        '-vf', 'scale=trunc(iw/2)*2:trunc(ih/2)*2',  # Ensure even dimensions for h264
        '-c:v', 'libx264',  # Re-encode video
        '-preset', 'fast',  # Faster encoding
        '-crf', '23',  # Quality (18-28, lower is better)
        '-c:a', 'aac',  # Re-encode audio
        '-b:a', '128k',  # Audio bitrate
        '-movflags', '+faststart',  # iOS optimization
        '-y',  # Overwrite
        output_path
    ]

    print(f"Re-encoding video (this may take a minute)...")
    print(f"Command: {' '.join(cmd)}")

    result = subprocess.run(cmd, capture_output=True, text=True)

    if result.returncode != 0:
        print(f"Error: {result.stderr}")
        return False

    print(f"✓ Successfully re-encoded video")
    return True


# Test with remote video
input_video = "/tmp/testvideo.mp4"
output_video = "/tmp/testvideo_reencoded.mp4"

if not os.path.exists(input_video):
    print(f"Error: {input_video} not found")
    print("Download it first:")
    print(f"  curl https://kwafy.com/api/v3/videos/724 --output {input_video}")
    sys.exit(1)

print("=" * 80)
print("RE-ENCODE VIDEO FOR IOS")
print("=" * 80)

print("\n1. Original video:")
result = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'stream=codec_type', input_video],
                       capture_output=True, text=True)
streams_before = result.stdout.count('codec_type')
print(f"   Streams: {streams_before}")
print(result.stdout)

print("\n2. Re-encoding...")
if not reencode_video_for_ios(input_video, output_video):
    sys.exit(1)

print("\n3. Re-encoded video:")
result = subprocess.run(['ffprobe', '-v', 'error', '-show_entries', 'stream=codec_type', output_video],
                       capture_output=True, text=True)
streams_after = result.stdout.count('codec_type')
print(f"   Streams: {streams_after}")
print(result.stdout)

if streams_after == 2:
    print("\n✓ SUCCESS: Video now has only 2 streams (video + audio)")
    print(f"✓ Re-encoded video saved to: {output_video}")
    print("\nNext steps:")
    print("1. Test this video in iOS app to confirm it plays")
    print("2. If it works, re-encode all production videos")
    print("3. Update upload script to re-encode before uploading")
else:
    print("\n✗ WARNING: Video still has unexpected streams")

print("=" * 80)
