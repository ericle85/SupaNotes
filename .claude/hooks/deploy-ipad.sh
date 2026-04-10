#!/bin/bash
# PostToolUse hook: install & launch on iPad after successful xcodebuild

input=$(cat)
tool=$(echo "$input" | jq -r '.tool_name // empty')
exit_code=$(echo "$input" | jq -r '.tool_result.exit_code // empty')
command=$(echo "$input" | jq -r '.tool_input.command // empty')

# Only run after successful xcodebuild build commands
if [ "$tool" != "Bash" ]; then exit 0; fi
if [ "$exit_code" != "0" ]; then exit 0; fi
if ! echo "$command" | grep -q "xcodebuild.*build"; then exit 0; fi
# Skip simulator builds
if echo "$command" | grep -q "Simulator"; then exit 0; fi

DEVICE="EF8608D0-800C-51D6-A568-89B77C07D32F"
BUNDLE_ID="ericle.SupaNotes"
APP="/Users/ericle/Library/Developer/Xcode/DerivedData/SupaNotes-adbzkvgcdbklvxehonsepjvvtypp/Build/Products/Debug-iphoneos/SupaNotes.app"

if [ ! -d "$APP" ]; then
    echo "No device build found, skipping deploy" >&2
    exit 0
fi

xcrun devicectl device install app --device "$DEVICE" "$APP" 2>&1
xcrun devicectl device process launch --device "$DEVICE" "$BUNDLE_ID" 2>&1
