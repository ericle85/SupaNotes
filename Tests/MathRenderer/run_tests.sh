#!/bin/bash
set -e
cd "$(dirname "$0")/../.."
rm -rf Tests/MathRenderer/output Tests/MathRenderer/output_clean
xcodebuild -project SupaNotes.xcodeproj -scheme SupaNotes \
  -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M3)' \
  -only-testing:Tests/MathRendererTests \
  test 2>&1 | grep -E "Test Case|passed|failed|error:" || true
echo ""
echo "With boxes:  Tests/MathRenderer/output/"
ls Tests/MathRenderer/output/*.png 2>/dev/null | wc -l | xargs -I{} echo "  {} images"
echo "Clean:       Tests/MathRenderer/output_clean/"
ls Tests/MathRenderer/output_clean/*.png 2>/dev/null | wc -l | xargs -I{} echo "  {} images"
