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

assert_file() {
  local name="$1"
  local pattern="$2"
  local count
  count=$(find "$TMPDIR_TEST" -name "$pattern" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [ "$count" -gt 0 ]; then
    echo "  ✅ $name (${count} files)"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $name (no files matching ${pattern})"
    FAIL=$((FAIL + 1))
  fi
}

echo "🧪 vshot smoke tests"
echo ""

# Generate a 3-second test video (solid color, no audio)
echo "   Generating test video..."
ffmpeg -v error -f lavfi -i "color=c=blue:s=640x360:d=3" \
  -c:v libx264 -t 3 -y "$VIDEO" 2>/dev/null

echo ""
echo "── Version ──"
assert "--version flag" "$VSHOT" --version

echo ""
echo "── Help ──"
assert "--help flag" "$VSHOT" --help

echo ""
echo "── Frame extraction ──"
assert "extract 3 frames" "$VSHOT" "$VIDEO" --frames 3 --output "${TMPDIR_TEST}/frames"
assert_file "frames exist" "vshot_*_frame_*.jpg"

echo ""
echo "── Montage ──"
assert "create montage" "$VSHOT" "$VIDEO" --montage --frames 3 --output "${TMPDIR_TEST}/montage"
assert_file "montage exists" "*_montage_*.jpg"

echo ""
echo "── Montage + cleanup ──"
assert "montage with cleanup" "$VSHOT" "$VIDEO" --montage --cleanup --frames 3 --output "${TMPDIR_TEST}/cleanup"
# After cleanup, individual frames should be gone
REMAINING=$(find "${TMPDIR_TEST}/cleanup" -name "vshot_*_frame_*.jpg" -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$REMAINING" -eq 0 ]; then
  echo "  ✅ individual frames cleaned up"
  PASS=$((PASS + 1))
else
  echo "  ❌ individual frames still present (${REMAINING})"
  FAIL=$((FAIL + 1))
fi

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
echo "── Error handling ──"
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
assert_fail "missing file errors" "$VSHOT" /nonexistent.mp4
assert_fail "invalid --frames errors" "$VSHOT" "$VIDEO" --frames -1
assert_fail "invalid --mode errors" "$VSHOT" "$VIDEO" --mode bogus
assert_fail "no args errors" "$VSHOT"

echo ""
echo "════════════════════════════"
echo "   ${PASS} passed, ${FAIL} failed"
echo "════════════════════════════"

[ "$FAIL" -eq 0 ]
