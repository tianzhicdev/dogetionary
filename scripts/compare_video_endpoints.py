#!/usr/bin/env python3
"""
Compare local and remote video endpoints to identify differences
"""

import requests
import subprocess
import os

LOCAL_URL = "http://localhost:5001"
REMOTE_URL = "https://kwafy.com/api"
LOCAL_VIDEO_ID = 11  # From local database
REMOTE_VIDEO_ID = 724  # From remote

print("=" * 80)
print("VIDEO ENDPOINT COMPARISON")
print("=" * 80)

# Test 1: Download both videos
print("\n1. Downloading videos...")
print("-" * 80)

local_video = f"/tmp/local_video_{LOCAL_VIDEO_ID}.mp4"
remote_video = f"/tmp/remote_video_{REMOTE_VIDEO_ID}.mp4"

# Download local
print(f"Downloading local video {LOCAL_VIDEO_ID}...")
r = requests.get(f"{LOCAL_URL}/v3/videos/{LOCAL_VIDEO_ID}")
with open(local_video, 'wb') as f:
    f.write(r.content)
print(f"  ✓ Downloaded {len(r.content)} bytes")
print(f"  Status: {r.status_code}")
print(f"  Headers: Content-Type={r.headers.get('Content-Type')}, Accept-Ranges={r.headers.get('Accept-Ranges')}")

# Download remote
print(f"\nDownloading remote video {REMOTE_VIDEO_ID}...")
r = requests.get(f"{REMOTE_URL}/v3/videos/{REMOTE_VIDEO_ID}")
with open(remote_video, 'wb') as f:
    f.write(r.content)
print(f"  ✓ Downloaded {len(r.content)} bytes")
print(f"  Status: {r.status_code}")
print(f"  Headers: Content-Type={r.headers.get('Content-Type')}, Accept-Ranges={r.headers.get('Accept-Ranges')}")

# Test 2: Compare video codecs
print("\n2. Comparing video codecs...")
print("-" * 80)

def get_video_info(path):
    cmd = f"ffprobe -v error -show_format -show_streams {path}"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return result.stdout

local_info = get_video_info(local_video)
remote_info = get_video_info(remote_video)

# Extract key info
def extract_codec_info(info):
    lines = info.split('\n')
    data = {}
    for line in lines:
        if '=' in line:
            key, val = line.split('=', 1)
            if key in ['codec_name', 'codec_type', 'format_name', 'duration']:
                data[key] = val
    return data

local_data = extract_codec_info(local_info)
remote_data = extract_codec_info(remote_info)

print("Local video:")
for k, v in sorted(local_data.items()):
    print(f"  {k}: {v}")

print("\nRemote video:")
for k, v in sorted(remote_data.items()):
    print(f"  {k}: {v}")

# Test 3: Check MP4 atom structure
print("\n3. Checking MP4 atom structure...")
print("-" * 80)

def check_mp4_atoms(path):
    with open(path, 'rb') as f:
        data = f.read(100)
    return {
        'has_ftyp': b'ftyp' in data,
        'has_moov_early': b'moov' in data,
        'first_20_bytes': data[:20].hex()
    }

local_atoms = check_mp4_atoms(local_video)
remote_atoms = check_mp4_atoms(remote_video)

print("Local video atoms:")
for k, v in local_atoms.items():
    print(f"  {k}: {v}")

print("\nRemote video atoms:")
for k, v in remote_atoms.items():
    print(f"  {k}: {v}")

# Test 4: Can they play with QuickTime?
print("\n4. Testing playback with QuickTime Player...")
print("-" * 80)

print("Testing local video...")
result = subprocess.run(['qlmanage', '-p', local_video], capture_output=True, timeout=3)
print(f"  Local video preview: {'✓ OK' if result.returncode == 0 else '✗ FAILED'}")

print("Testing remote video...")
result = subprocess.run(['qlmanage', '-p', remote_video], capture_output=True, timeout=3)
print(f"  Remote video preview: {'✓ OK' if result.returncode == 0 else '✗ FAILED'}")

# Test 5: iOS AVPlayer compatibility check
print("\n5. iOS AVPlayer Compatibility...")
print("-" * 80)

def check_ios_compatibility(path):
    # Check for common iOS playback issues
    cmd = f"ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,profile,pix_fmt,level -of default=noprint_wrappers=1 {path}"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    video_info = result.stdout

    cmd = f"ffprobe -v error -select_streams a:0 -show_entries stream=codec_name,sample_rate -of default=noprint_wrappers=1 {path}"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    audio_info = result.stdout

    return {'video': video_info.strip(), 'audio': audio_info.strip()}

print("Local video compatibility:")
local_compat = check_ios_compatibility(local_video)
print(f"  Video: {local_compat['video']}")
print(f"  Audio: {local_compat['audio']}")

print("\nRemote video compatibility:")
remote_compat = check_ios_compatibility(remote_video)
print(f"  Video: {remote_compat['video']}")
print(f"  Audio: {remote_compat['audio']}")

# Test 6: Check if moov atom is at beginning (faststart)
print("\n6. Checking moov atom position (iOS streaming requirement)...")
print("-" * 80)

def is_faststart(path):
    cmd = f"ffprobe -v quiet -show_format {path}"
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)

    # Also check with hexdump
    with open(path, 'rb') as f:
        first_kb = f.read(1024)

    moov_pos = first_kb.find(b'moov')
    mdat_pos = first_kb.find(b'mdat')

    return {
        'moov_in_first_kb': moov_pos > 0,
        'mdat_in_first_kb': mdat_pos > 0,
        'moov_before_mdat': moov_pos < mdat_pos if moov_pos > 0 and mdat_pos > 0 else None,
        'moov_position': moov_pos,
        'mdat_position': mdat_pos
    }

local_faststart = is_faststart(local_video)
remote_faststart = is_faststart(remote_video)

print("Local video:")
for k, v in local_faststart.items():
    print(f"  {k}: {v}")

print("\nRemote video:")
for k, v in remote_faststart.items():
    print(f"  {k}: {v}")

print("\n" + "=" * 80)
print("SUMMARY")
print("=" * 80)

if local_faststart == remote_faststart and local_data == remote_data:
    print("✓ Videos appear IDENTICAL in structure and codec")
    print("  → Problem is likely in iOS app configuration or network layer")
    print("  → Check:")
    print("     1. iOS Console logs when trying to play remote video")
    print("     2. App Transport Security settings")
    print("     3. VideoService download/caching logic")
    print("     4. AVPlayer error messages")
else:
    print("✗ Videos have DIFFERENCES:")
    if local_faststart != remote_faststart:
        print("  → Different MP4 atom structure (faststart)")
    if local_data != remote_data:
        print("  → Different codec/format properties")

print("=" * 80)
