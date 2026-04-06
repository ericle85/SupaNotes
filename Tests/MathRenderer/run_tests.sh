#!/bin/bash
set -e
cd "$(dirname "$0")/../.."
rm -rf Tests/MathRenderer/output Tests/MathRenderer/output_clean

DEVICE_ID="D9281340-20A0-41E0-895A-F24921E112C2"
BUILD_DIR="$(pwd)/build"
XCTEST_PATH="$BUILD_DIR/Debug-iphonesimulator/Tests.xctest"

# Build only the standalone Tests target (~4 math files)
xcodebuild -target Tests -configuration Debug \
  -sdk iphonesimulator \
  SYMROOT="$BUILD_DIR" \
  build 2>&1 | tail -3

# Boot simulator if needed
xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true

# Install and run the xctest bundle via simctl
xcrun simctl spawn "$DEVICE_ID" \
  /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/Library/Xcode/Agents/xctest \
  "$XCTEST_PATH" 2>&1 | grep -E "Test Case|Executed|passed|failed|error:" || true

echo ""
echo "With boxes:  Tests/MathRenderer/output/"
ls Tests/MathRenderer/output/*.png 2>/dev/null | wc -l | xargs -I{} echo "  {} images"
echo "Clean:       Tests/MathRenderer/output_clean/"
ls Tests/MathRenderer/output_clean/*.png 2>/dev/null | wc -l | xargs -I{} echo "  {} images"
