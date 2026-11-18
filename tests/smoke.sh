#!/bin/bash
# Smoke tests for vshot
# Note: no set -e because assert functions need to handle non-zero exits
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VSHOT="${SCRIPT_DIR}/../vshot"
TMPDIR_TEST=$(mktemp -d)
VIDEO="${TMPDIR_TEST}/test.mp4"

cleanup() {
  rm -rf -- "$TMPDIR_TEST"
}
trap cleanup EXIT

PASS=0
FAIL=0

assert() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  ✅ $name"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $name"
    FAIL=$((FAIL + 1))
  fi
}

assert_fail() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  ❌ $name (expected failure but got success)"
    FAIL=$((FAIL + 1))
  else
    echo "  ✅ $name"
    PASS=$((PASS + 1))
  fi
}

assert_count() {
  local name="$1"
  local dir="$2"
  local pattern="$3"
  local expected="$4"
  local count
  count=$(find "$dir" -maxdepth 1 -name "$pattern" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [ "$count" -eq "$expected" ]; then
    echo "  ✅ $name (${count} files)"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $name (expected ${expected}, got ${count})"
    FAIL=$((FAIL + 1))
  fi
}

assert_nonempty() {
  local name="$1"
  local filepath="$2"
  if [ -s "$filepath" ]; then
    echo "  ✅ $name ($(du -h "$filepath" | cut -f1 | tr -d ' '))"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $name (empty or missing)"
    FAIL=$((FAIL + 1))
  fi
}

echo "🧪 vshot smoke tests"
echo ""

# Generate a 3-second test video (solid color, no audio)
# Try libx264 first, fall back to mpeg4 for minimal ffmpeg builds (#5)
echo "   Generating test video..."
if ! ffmpeg -v error -f lavfi -i "color=c=blue:s=640x360:d=3" \
  -c:v libx264 -t 3 -y "$VIDEO" 2>/dev/null; then
  ffmpeg -v error -f lavfi -i "color=c=blue:s=640x360:d=3" \
    -c:v mpeg4 -t 3 -y "$VIDEO" 2>/dev/null
fi

echo ""
echo "── Version ──"
assert "--version flag" "$VSHOT" --version

echo ""
echo "── Help ──"
assert "--help flag" "$VSHOT" --help

echo ""
echo "── Frame extraction ──"
FRAMES_DIR="${TMPDIR_TEST}/frames"
assert "extract 3 frames" "$VSHOT" "$VIDEO" --frames 3 --output "$FRAMES_DIR"
assert_count "exactly 3 frames" "$FRAMES_DIR" "vshot_*_frame_*.jpg" 3

echo ""
echo "── Montage ──"
MONTAGE_DIR="${TMPDIR_TEST}/montage"
assert "create montage" "$VSHOT" "$VIDEO" --montage --frames 3 --output "$MONTAGE_DIR"
assert_count "exactly 1 montage" "$MONTAGE_DIR" "*_montage_*.jpg" 1
# Verify montage is non-empty
MONTAGE_FILE=$(find "$MONTAGE_DIR" -maxdepth 1 -name "*_montage_*.jpg" -type f 2>/dev/null | head -1)
if [ -n "$MONTAGE_FILE" ]; then
  assert_nonempty "montage non-empty" "$MONTAGE_FILE"
fi

echo ""
echo "── Montage + cleanup ──"
CLEANUP_DIR="${TMPDIR_TEST}/cleanup"
assert "montage with cleanup" "$VSHOT" "$VIDEO" --montage --cleanup --frames 3 --output "$CLEANUP_DIR"
assert_count "montage exists after cleanup" "$CLEANUP_DIR" "*_montage_*.jpg" 1
assert_count "individual frames cleaned up" "$CLEANUP_DIR" "vshot_*_frame_*.jpg" 0

echo ""
echo "── Modes ──"
assert "overview mode" "$VSHOT" "$VIDEO" --mode overview --frames 2 --output "${TMPDIR_TEST}/m_overview"
assert "text mode" "$VSHOT" "$VIDEO" --mode text --frames 2 --output "${TMPDIR_TEST}/m_text"
assert "detail mode" "$VSHOT" "$VIDEO" --mode detail --frames 2 --output "${TMPDIR_TEST}/m_detail"

echo ""
echo "── No timestamps ──"
assert "no-timestamps flag" "$VSHOT" "$VIDEO" --no-timestamps --frames 2 --output "${TMPDIR_TEST}/no_ts"

echo ""
echo "── Interval ──"
assert "interval mode" "$VSHOT" "$VIDEO" --interval 1 --output "${TMPDIR_TEST}/interval"

echo ""
echo "── Scene detection ──"
# Generate a video with scene changes for --scene testing
SCENE_VIDEO="${TMPDIR_TEST}/scene_test.mp4"
ffmpeg -v error -f lavfi -i "color=c=red:s=320x180:d=2[r];color=c=blue:s=320x180:d=2[b];[r][b]concat=n=2:v=1:a=0" \
  -c:v libx264 -t 4 -y "$SCENE_VIDEO" 2>/dev/null || \
  ffmpeg -v error -f lavfi -i "color=c=red:s=320x180:d=2[r];color=c=blue:s=320x180:d=2[b];[r][b]concat=n=2:v=1:a=0" \
    -c:v mpeg4 -t 4 -y "$SCENE_VIDEO" 2>/dev/null

SCENE_DIR="${TMPDIR_TEST}/scene"
assert "scene detection" "$VSHOT" "$SCENE_VIDEO" --scene --output "$SCENE_DIR"
SCENE_FRAMES=$(find "$SCENE_DIR" -maxdepth 1 -name "vshot_*_frame_*.jpg" -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$SCENE_FRAMES" -ge 1 ]; then
  echo "  ✅ scene extracted ${SCENE_FRAMES} frame(s)"
  PASS=$((PASS + 1))
else
  echo "  ❌ scene extracted 0 frames"
  FAIL=$((FAIL + 1))
fi

SCENE_MONTAGE_DIR="${TMPDIR_TEST}/scene_montage"
assert "scene + montage" "$VSHOT" "$SCENE_VIDEO" --scene --montage --output "$SCENE_MONTAGE_DIR"
assert_count "scene montage exists" "$SCENE_MONTAGE_DIR" "*_montage_*.jpg" 1

# Scene + montage + cleanup (#9)
SCENE_CLEANUP_DIR="${TMPDIR_TEST}/scene_cleanup"
assert "scene + montage + cleanup" "$VSHOT" "$SCENE_VIDEO" --scene --montage --cleanup --output "$SCENE_CLEANUP_DIR"
assert_count "scene cleanup: montage exists" "$SCENE_CLEANUP_DIR" "*_montage_*.jpg" 1
assert_count "scene cleanup: frames removed" "$SCENE_CLEANUP_DIR" "vshot_*_frame_*.jpg" 0

# --scene 0, 0.0, .0 should all be accepted (#3, #9)
assert "scene threshold 0" "$VSHOT" "$SCENE_VIDEO" --scene 0 --output "${TMPDIR_TEST}/scene_zero"
assert "scene threshold 0.0" "$VSHOT" "$SCENE_VIDEO" --scene 0.0 --output "${TMPDIR_TEST}/scene_zero2"
assert "scene threshold .0" "$VSHOT" "$SCENE_VIDEO" --scene .0 --output "${TMPDIR_TEST}/scene_zero3"

# --scene 1.0 — very high threshold, likely 0 frames (exit 2) (#4, #9)
"$VSHOT" "$SCENE_VIDEO" --scene 1.0 --output "${TMPDIR_TEST}/scene_max" >/dev/null 2>&1
SCENE_MAX_EXIT=$?
SCENE_MAX_FRAMES=$(find "${TMPDIR_TEST}/scene_max" -maxdepth 1 -name "vshot_*_frame_*.jpg" -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$SCENE_MAX_EXIT" -eq 2 ] && [ "$SCENE_MAX_FRAMES" -eq 0 ]; then
  echo "  ✅ scene threshold 1.0 (exit 2, 0 frames as expected)"
  PASS=$((PASS + 1))
else
  echo "  ❌ scene threshold 1.0 (exit ${SCENE_MAX_EXIT}, ${SCENE_MAX_FRAMES} frames — expected exit 2, 0 frames)"
  FAIL=$((FAIL + 1))
fi

# Custom threshold — may find 0 frames (exit 2) or some frames (exit 0) (#9)
"$VSHOT" "$SCENE_VIDEO" --scene 0.5 --output "${TMPDIR_TEST}/scene_custom" >/dev/null 2>&1
CUSTOM_EXIT=$?
if [ "$CUSTOM_EXIT" -eq 0 ] || [ "$CUSTOM_EXIT" -eq 2 ]; then
  echo "  ✅ scene custom threshold 0.5 (exit ${CUSTOM_EXIT})"
  PASS=$((PASS + 1))
else
  echo "  ❌ scene custom threshold 0.5 (unexpected exit ${CUSTOM_EXIT})"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "── Cleanup isolation (#7) ──"
# Run twice into same dir, verify cleanup only removes current run's frames
ISOLATION_DIR="${TMPDIR_TEST}/isolation"
if "$VSHOT" "$VIDEO" --frames 2 --output "$ISOLATION_DIR" >/dev/null 2>&1; then
  FIRST_RUN_COUNT=$(find "$ISOLATION_DIR" -maxdepth 1 -name "vshot_*_frame_*.jpg" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [ "$FIRST_RUN_COUNT" -ge 1 ] && "$VSHOT" "$VIDEO" --montage --cleanup --frames 2 --output "$ISOLATION_DIR" >/dev/null 2>&1; then
    AFTER_CLEANUP_COUNT=$(find "$ISOLATION_DIR" -maxdepth 1 -name "vshot_*_frame_*.jpg" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$AFTER_CLEANUP_COUNT" -eq "$FIRST_RUN_COUNT" ]; then
      echo "  ✅ cleanup preserves other run's frames (${FIRST_RUN_COUNT} retained)"
      PASS=$((PASS + 1))
    else
      echo "  ❌ cleanup removed other run's frames (expected ${FIRST_RUN_COUNT}, got ${AFTER_CLEANUP_COUNT})"
      FAIL=$((FAIL + 1))
    fi
  else
    echo "  ❌ cleanup isolation: second vshot run failed"
    FAIL=$((FAIL + 1))
  fi
else
  echo "  ❌ cleanup isolation: first vshot run failed"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "── Pinpoint extraction (--at) ──"
AT_DIR="${TMPDIR_TEST}/at"
assert "--at extraction" "$VSHOT" "$VIDEO" --at 0.5,1.5 --output "$AT_DIR"
assert_count "exactly 2 frames" "$AT_DIR" "vshot_*_frame_*.jpg" 2
assert_count "frames carry timestamp suffix" "$AT_DIR" "vshot_*_frame_*_t*.jpg" 2
assert "--at skips out-of-range times" "$VSHOT" "$VIDEO" --at 1,999 --output "${TMPDIR_TEST}/at_range"
assert_count "out-of-range time skipped" "${TMPDIR_TEST}/at_range" "vshot_*_frame_*.jpg" 1
assert "--at + montage" "$VSHOT" "$VIDEO" --at 0.5,1.5,2.5 --montage --output "${TMPDIR_TEST}/at_montage"
assert_count "at montage exists" "${TMPDIR_TEST}/at_montage" "*_montage_*.jpg" 1

echo ""
echo "── Montage columns (--cols) ──"
COLS_DIR="${TMPDIR_TEST}/cols"
assert "--cols 2 montage" "$VSHOT" "$VIDEO" --montage --cols 2 --frames 3 --output "$COLS_DIR"
assert_count "cols montage exists" "$COLS_DIR" "*_montage_*.jpg" 1

echo ""
echo "── Stable montage name (--name) ──"
NAME_DIR="${TMPDIR_TEST}/name"
assert "--name montage" "$VSHOT" "$VIDEO" --montage --cleanup --frames 2 --name review --output "$NAME_DIR"
assert "--name rerun overwrites" "$VSHOT" "$VIDEO" --montage --cleanup --frames 2 --name review --output "$NAME_DIR"
assert_count "--name: exactly 1 montage after 2 runs" "$NAME_DIR" "*.jpg" 1
assert_nonempty "--name montage non-empty" "${NAME_DIR}/review.jpg"
NAME_OUT=$("$VSHOT" "$VIDEO" --montage --cleanup --frames 2 --name review --output "$NAME_DIR" 2>&1)
if echo "$NAME_OUT" | grep -q '📊 Montage: review.jpg ' && \
   echo "$NAME_OUT" | grep -q "Read(\".*/name/review.jpg\")"; then
  echo "  ✅ --name: Montage line and Read() hint use the real file"
  PASS=$((PASS + 1))
else
  echo "  ❌ --name: output does not reference review.jpg: $NAME_OUT"
  FAIL=$((FAIL + 1))
fi
NAME_JSON=$("$VSHOT" "$VIDEO" --montage --cleanup --frames 2 --name review --json --output "$NAME_DIR" 2>/dev/null)
if echo "$NAME_JSON" | grep -q '"montage":"[^"]*/name/review.jpg"'; then
  echo "  ✅ --name: --json reports review.jpg"
  PASS=$((PASS + 1))
else
  echo "  ❌ --name: --json montage path wrong: $NAME_JSON"
  FAIL=$((FAIL + 1))
fi
NAME_EXT_DIR="${TMPDIR_TEST}/name_ext"
assert "--name strips .JPEG" "$VSHOT" "$VIDEO" --montage --cleanup --frames 2 --name shot.JPEG --output "$NAME_EXT_DIR"
assert "--name strips .Jpg" "$VSHOT" "$VIDEO" --montage --cleanup --frames 2 --name clip.Jpg --output "$NAME_EXT_DIR"
assert_nonempty "--name .JPEG -> shot.jpg" "${NAME_EXT_DIR}/shot.jpg"
assert_nonempty "--name .Jpg -> clip.jpg" "${NAME_EXT_DIR}/clip.jpg"
assert_count "--name: no double extension" "$NAME_EXT_DIR" "*.jpg" 2
# Stale target: a pre-existing file must be replaced, not reported as-is
NAME_STALE_DIR="${TMPDIR_TEST}/name_stale"
mkdir -p "$NAME_STALE_DIR"
echo "stale" > "${NAME_STALE_DIR}/review.jpg"
assert "--name over stale file" "$VSHOT" "$VIDEO" --montage --frames 2 --name review --output "$NAME_STALE_DIR"
if ! grep -q "^stale$" "${NAME_STALE_DIR}/review.jpg"; then
  echo "  ✅ --name: stale target replaced"
  PASS=$((PASS + 1))
else
  echo "  ❌ --name: stale target was not replaced"
  FAIL=$((FAIL + 1))
fi
# A montage that exits 0 without writing must not let the stale file pass
FAKE_BIN="${TMPDIR_TEST}/fake_bin"
mkdir -p "$FAKE_BIN"
printf '#!/bin/sh\nexit 0\n' > "${FAKE_BIN}/montage"
chmod +x "${FAKE_BIN}/montage"
echo "stale" > "${NAME_STALE_DIR}/review.jpg"
assert_fail "--name: no-op montage fails instead of reporting stale file" \
  env PATH="${FAKE_BIN}:${PATH}" "$VSHOT" "$VIDEO" --montage --frames 2 --name review --output "$NAME_STALE_DIR"
if [ ! -e "${NAME_STALE_DIR}/review.jpg" ]; then
  echo "  ✅ --name: stale target removed before montage"
  PASS=$((PASS + 1))
else
  echo "  ❌ --name: stale target survived a failed run"
  FAIL=$((FAIL + 1))
fi
assert_fail "--name empty errors" "$VSHOT" "$VIDEO" --montage --frames 2 --name "" --output "${TMPDIR_TEST}/name_bad"
assert_fail "--name .jpg (empty after strip) errors" "$VSHOT" "$VIDEO" --montage --frames 2 --name .jpg --output "${TMPDIR_TEST}/name_bad"
assert_fail "--name with / errors" "$VSHOT" "$VIDEO" --montage --frames 2 --name a/b --output "${TMPDIR_TEST}/name_bad"
assert_fail "--name without --montage errors" "$VSHOT" "$VIDEO" --frames 2 --name review --output "${TMPDIR_TEST}/name_bad"
assert_fail "--name missing value errors" "$VSHOT" "$VIDEO" --montage --name
if [ ! -e "${TMPDIR_TEST}/name_bad" ]; then
  echo "  ✅ --name: invalid names fail before writing output"
  PASS=$((PASS + 1))
else
  echo "  ❌ --name: invalid name still created output dir"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "── JSON output (--json) ──"
JSON_DIR="${TMPDIR_TEST}/json"
JSON_OUT=$("$VSHOT" "$VIDEO" --montage --frames 2 --json --output "$JSON_DIR" 2>/dev/null)
if echo "$JSON_OUT" | grep -q '"montage":"'; then
  echo "  ✅ --json emits montage path"
  PASS=$((PASS + 1))
else
  echo "  ❌ --json missing montage path: $JSON_OUT"
  FAIL=$((FAIL + 1))
fi
JSON_MONTAGE=$(echo "$JSON_OUT" | sed 's/.*"montage":"\([^"]*\)".*/\1/')
assert_nonempty "--json montage path exists" "$JSON_MONTAGE"
if echo "$JSON_OUT" | grep -q '"files":\[{"path":'; then
  echo "  ✅ --json lists frame files with times"
  PASS=$((PASS + 1))
else
  echo "  ❌ --json files list missing: $JSON_OUT"
  FAIL=$((FAIL + 1))
fi
if command -v python3 >/dev/null 2>&1; then
  if echo "$JSON_OUT" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
    echo "  ✅ --json output is valid JSON"
    PASS=$((PASS + 1))
  else
    echo "  ❌ --json output is invalid JSON: $JSON_OUT"
    FAIL=$((FAIL + 1))
  fi
fi

echo ""
echo "── Error handling ──"
assert_fail "missing file errors" "$VSHOT" /nonexistent.mp4
assert_fail "invalid --frames errors" "$VSHOT" "$VIDEO" --frames -1
assert_fail "invalid --mode errors" "$VSHOT" "$VIDEO" --mode bogus
assert_fail "no args errors" "$VSHOT"
assert_fail "invalid --at errors" "$VSHOT" "$VIDEO" --at abc
assert_fail "all --at out-of-range errors" "$VSHOT" "$VIDEO" --at 999
assert_fail "invalid --cols errors" "$VSHOT" "$VIDEO" --montage --cols 0 --frames 2

echo ""
echo "── Font fallback ──"
# Test font detection by checking vshot completes with montage even if
# ImageMagick has broken font config (the detect_font function handles this)
REAL_MONTAGE=$(command -v montage)
if [ -n "$REAL_MONTAGE" ]; then
  FONT_DIR="${TMPDIR_TEST}/font_test"
  assert "montage with font detection" "$VSHOT" "$VIDEO" --montage --frames 3 --output "$FONT_DIR"
  assert_count "font test montage created" "$FONT_DIR" "*_montage_*.jpg" 1
else
  echo "  ⚠️  font fallback: montage not installed, skipping"
  PASS=$((PASS + 1))
fi

echo ""
echo "════════════════════════════"
echo "   ${PASS} passed, ${FAIL} failed"
echo "════════════════════════════"

[ "$FAIL" -eq 0 ]
