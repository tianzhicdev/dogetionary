# Fix Remote Database Videos - Remove bin_data Streams

## Problem
Remote videos have `bin_data` (subtitle/text) streams that cause iOS AVPlayer to fail.

## Solution
Process all videos in the remote database to remove the data streams.

## Steps

### 1. Connect to remote server
```bash
~/projects/to_kwafy.sh
su - tianzhic
```

### 2. Find the postgres container
```bash
docker ps --filter "name=postgres"
```

### 3. Create a temporary script on the server

```bash
cat > /tmp/fix_videos.sh << 'EOF'
#!/bin/bash
# Fix all videos in database by removing data streams

CONTAINER=$(docker ps --filter "name=postgres" --format "{{.Names}}" | head -1)

if [ -z "$CONTAINER" ]; then
    echo "Error: Postgres container not found"
    exit 1
fi

echo "=== Fixing Videos in Database ==="
echo "Container: $CONTAINER"

# Get count of videos
COUNT=$(docker exec -i "$CONTAINER" psql -U dogeuser -d dogetionary -tA -c "SELECT COUNT(*) FROM videos;")
echo "Total videos: $COUNT"

# Export each video, fix it, and reimport
docker exec -i "$CONTAINER" psql -U dogeuser -d dogetionary -tA -c "
SELECT id FROM videos ORDER BY id;
" | while read -r video_id; do
    echo "Processing video ID: $video_id"

    # Export video to temp file
    docker exec -i "$CONTAINER" psql -U dogeuser -d dogetionary -c "
        \\copy (SELECT video_data FROM videos WHERE id = $video_id) TO '/tmp/video_${video_id}.bin' WITH BINARY
    "

    # Fix the video (remove data streams)
    docker exec -i "$CONTAINER" bash -c "
        ffmpeg -i /tmp/video_${video_id}.bin \
            -map 0:v -map 0:a \
            -c copy \
            -movflags +faststart \
            -y /tmp/video_${video_id}_fixed.mp4 2>/dev/null

        if [ \$? -eq 0 ]; then
            echo '  ✓ Fixed video $video_id'
        else
            echo '  ✗ Failed to fix video $video_id'
            exit 1
        fi
    "

    # Import fixed video back to database
    docker exec -i "$CONTAINER" psql -U dogeuser -d dogetionary -c "
        UPDATE videos
        SET video_data = pg_read_binary_file('/tmp/video_${video_id}_fixed.mp4')
        WHERE id = $video_id;
    "

    # Cleanup
    docker exec -i "$CONTAINER" bash -c "
        rm /tmp/video_${video_id}.bin /tmp/video_${video_id}_fixed.mp4
    "

    echo "  ✓ Updated database"
done

echo "=== Done ==="
EOF

chmod +x /tmp/fix_videos.sh
```

### 4. Run the fix script
```bash
/tmp/fix_videos.sh
```

## Alternative: Simpler approach using pg_largeobject

If the above doesn't work due to permissions, you can:

1. Download all videos from the API
2. Fix them locally with ffmpeg
3. Re-upload via the API using the fixed upload script

## Test First
Before fixing all videos, test with one video:

```bash
# Download video 724
curl https://kwafy.com/api/v3/videos/724 --output /tmp/test_video.mp4

# Fix it
ffmpeg -i /tmp/test_video.mp4 -map 0:v -map 0:a -c copy -movflags +faststart -y /tmp/test_fixed.mp4

# Check streams (should only have video + audio)
ffprobe -v error -show_entries stream=codec_type /tmp/test_fixed.mp4

# Test in iOS app to confirm it works
```

## Future Prevention
The `upload_from_catalog.py` script has been updated to automatically strip data streams before uploading.
All future uploads will not have this issue.
