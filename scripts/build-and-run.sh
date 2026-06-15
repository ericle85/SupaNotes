#!/bin/bash
# Build, install, and launch SupaNotes on iPad
set -e

SCHEME="SupaNotes"
CONFIG="Debug"
DEVICE_UDID="00008122-000661223EB9801C"
DEVICE_ECID="EF8608D0-800C-51D6-A568-89B77C07D32F"
WORKSPACE="/Users/ericle/SwiftProjects/SupaNotes/SupaNotes.xcodeproj/project.xcworkspace"
APP_PATH="/Users/ericle/Library/Developer/Xcode/DerivedData/SupaNotes-adbzkvgcdbklvxehonsepjvvtypp/Build/Products/Debug-iphoneos/SupaNotes.app"

echo "🔨 Building..."
xcodebuild -scheme "$SCHEME" -configuration "$CONFIG" \
  -destination "platform=iOS,id=$DEVICE_UDID" \
  -allowProvisioningUpdates \
  -workspace "$WORKSPACE" \
  build 2>&1 | tail -5

echo "📲 Installing..."
xcrun devicectl device install app --device "$DEVICE_ECID" "$APP_PATH"

echo "🚀 Launching..."
xcrun devicectl device process launch --terminate-existing --device "$DEVICE_ECID" ericle.SupaNotes

echo "✅ Done"
