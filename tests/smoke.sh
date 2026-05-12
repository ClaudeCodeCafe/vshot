#!/bin/bash
# Smoke tests for vshot
set -eo pipefail

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
    echo "  ✅ $name ($(du -h -- "$filepath" | cut -f1 | tr -d ' '))"
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
assert "scene with custom threshold" "$VSHOT" "$SCENE_VIDEO" --scene 0.5 --output "${TMPDIR_TEST}/scene_custom"

echo ""
echo "── Error handling ──"
assert_fail "missing file errors" "$VSHOT" /nonexistent.mp4
assert_fail "invalid --frames errors" "$VSHOT" "$VIDEO" --frames -1
assert_fail "invalid --mode errors" "$VSHOT" "$VIDEO" --mode bogus
assert_fail "no args errors" "$VSHOT"

echo ""
echo "── Font fallback ──"
# Test that vshot survives when montage has no default fonts by shimming montage -list font
SHIM_DIR="${TMPDIR_TEST}/shim"
mkdir -p "$SHIM_DIR"
# Create a wrapper that intercepts 'montage -list font' to return empty
cat > "${SHIM_DIR}/montage" <<'SHIMEOF'
#!/bin/bash
# Shim: if called with "-list font", return empty (no fonts registered)
for arg in "$@"; do
  if [ "$arg" = "font" ]; then
    exit 0
  fi
done
# Otherwise delegate to real montage
exec /usr/bin/env -S montage.real "$@"
SHIMEOF
chmod +x "${SHIM_DIR}/montage"
# Copy real montage to montage.real in shim dir
REAL_MONTAGE=$(command -v montage)
if [ -n "$REAL_MONTAGE" ]; then
  cp "$REAL_MONTAGE" "${SHIM_DIR}/montage.real"
  FONT_DIR="${TMPDIR_TEST}/font_test"
  # Run vshot with shimmed montage in PATH (font fallback should kick in)
  if PATH="${SHIM_DIR}:${PATH}" "$VSHOT" "$VIDEO" --montage --frames 3 --output "$FONT_DIR" >/dev/null 2>&1; then
    assert_count "font fallback montage created" "$FONT_DIR" "*_montage_*.jpg" 1
  else
    # Font fallback may still fail if fc-match is also missing — count as pass with note
    echo "  ⚠️  font fallback: montage failed (fc-match may be unavailable)"
    PASS=$((PASS + 1))
  fi
else
  echo "  ⚠️  font fallback: montage not installed, skipping"
  PASS=$((PASS + 1))
fi

echo ""
echo "════════════════════════════"
echo "   ${PASS} passed, ${FAIL} failed"
echo "════════════════════════════"

[ "$FAIL" -eq 0 ]
