import json
import os
import subprocess
import sys

TESTS_DIR = os.path.dirname(__file__)
REPO_ROOT = os.path.join(TESTS_DIR, "..")
SWIFT_CLI_SRC = os.path.join(TESTS_DIR, "swift_placement_cli.swift")
SUGGESTION_PLACEMENT_SRC = os.path.join(
    REPO_ROOT, "SupaNotesSwift", "SupaNotesSwift", "Autocomplete", "SuggestionPlacement.swift"
)
SWIFT_CLI_BIN = "/tmp/placement_cli"
STROKES_DIR = os.path.expanduser("~/Downloads/strokes_exported/alignWithEquals")


def build_swift_cli():
    result = subprocess.run(
        ["swiftc", SWIFT_CLI_SRC, SUGGESTION_PLACEMENT_SRC, "-o", SWIFT_CLI_BIN],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"Swift build failed:\n{result.stderr}")
        sys.exit(1)


def run_swift_cli(inkml_path):
    result = subprocess.run(
        [SWIFT_CLI_BIN, inkml_path],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None
    return json.loads(result.stdout)


def run_tests():
    build_swift_cli()

    folders = sorted(
        f
        for f in os.listdir(STROKES_DIR)
        if os.path.isdir(os.path.join(STROKES_DIR, f)) and f.startswith("strokes_")
    )

    passed = 0
    failed = 0

    for folder in folders:
        folder_path = os.path.join(STROKES_DIR, folder)
        inkml_files = [f for f in os.listdir(folder_path) if f.endswith(".inkml")]
        if not inkml_files:
            print(f"  SKIP  {folder} (no inkml)")
            continue

        inkml_path = os.path.join(folder_path, inkml_files[0])
        result = run_swift_cli(inkml_path)

        if result is None:
            print(f"  FAIL  {folder}  swift cli error")
            failed += 1
            continue

        center = result.get("equal_sign_center")
        if center is not None:
            print(f"  PASS  {folder}  center=({center['x']:.1f}, {center['y']:.1f})")
            passed += 1
        else:
            print(f"  FAIL  {folder}  equal_sign_center is null")
            failed += 1

    print(f"\n{passed} passed, {failed} failed, {len(folders)} total")
    return failed == 0


if __name__ == "__main__":
    success = run_tests()
    sys.exit(0 if success else 1)
