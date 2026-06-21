SupaNotes

Making a handwriting notetaking app for ipad. App isn't in production yet, so don't worry about breaking changes or backwards compatibility. 

Rules:
    How we write code
    - Functional programming
    - Zero comments to be written
    
    Swift lint & swift format commands to be run after all changes are made.

After every change, you are to:
- Build on ipad air 11 inch (M3)

After every feature is made: 
- Send out a QA to test the feature, point out \QA_tools

## Recording a QA run as video

When recording a UITest run on the simulator, stop the recorder with a graceful `SIGINT` — never a hard kill. A hard kill (e.g. killing the background process abruptly) leaves the mp4 unfinalized (missing moov atom) and QuickTime reports it as incompatible/corrupted.

Use this one-shot pattern so the video finalizes correctly:

```bash
SIM=D9281340-20A0-41E0-895A-F24921E112C2  # iPad Air 11-inch (M3)
xcrun simctl io $SIM recordVideo --codec=h264 --force qa-run.mp4 &
REC=$!; sleep 2
xcodebuild -scheme SupaNotes -destination "platform=iOS Simulator,id=$SIM" \
  -only-testing:UITests -parallel-testing-enabled NO test-without-building
kill -INT $REC; wait $REC
```

- `kill -INT` (not a hard kill) lets `simctl` print "Recording completed. Writing to disk." and write a valid file.
- `-parallel-testing-enabled NO` keeps the run on the visible booted sim instead of a hidden clone, so the recording captures the actual interaction.