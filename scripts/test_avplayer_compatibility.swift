#!/usr/bin/env swift

import AVFoundation
import Foundation

// Test if AVPlayer can play the downloaded videos

print("Testing AVPlayer compatibility with local and remote videos")
print(String(repeating: "=", count: 80))

// Test local video
let localVideoURL = URL(fileURLWithPath: "/tmp/local_video_11.mp4")
print("\n1. Testing LOCAL video: \(localVideoURL.path)")
let localPlayer = AVPlayer(url: localVideoURL)
print("   Status: \(localPlayer.status.rawValue)")
print("   Current item: \(localPlayer.currentItem != nil ? "✓" : "✗")")
if let error = localPlayer.currentItem?.error {
    print("   Error: \(error.localizedDescription)")
}

// Test remote video
let remoteVideoURL = URL(fileURLWithPath: "/tmp/testvideo.mp4")
print("\n2. Testing REMOTE video: \(remoteVideoURL.path)")
let remotePlayer = AVPlayer(url: remoteVideoURL)
print("   Status: \(remotePlayer.status.rawValue)")
print("   Current item: \(remotePlayer.currentItem != nil ? "✓" : "✗")")
if let error = remotePlayer.currentItem?.error {
    print("   Error: \(error.localizedDescription)")
}

// Give players time to load
sleep(2)

print("\n3. After 2 seconds:")
print("   Local player status: \(localPlayer.status.rawValue)")
print("   Remote player status: \(remotePlayer.status.rawValue)")

if localPlayer.status == .readyToPlay && remotePlayer.status == .readyToPlay {
    print("\n✓ Both videos are ready to play - THEY SHOULD WORK")
} else if localPlayer.status == .readyToPlay && remotePlayer.status != .readyToPlay {
    print("\n✗ Local works but remote FAILS - Confirms the bin_data stream issue")
} else {
    print("\n? Unexpected result - check file paths")
}
