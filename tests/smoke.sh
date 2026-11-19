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
# Default mode picks the first frame at or after i * D / N (#10)
assert_count "frame 1 at 0s" "$FRAMES_DIR" "vshot_*_frame_0001_t0m00s.jpg" 1
assert_count "frame 2 at 1s" "$FRAMES_DIR" "vshot_*_frame_0002_t0m01s.jpg" 1
assert_count "frame 3 at 2s" "$FRAMES_DIR" "vshot_*_frame_0003_t0m02s.jpg" 1

# Container longer than the video stream (audio tail): times past the last
# video frame are skipped, remaining frames keep their own timestamps (#10)
TAIL_VIDEO="${TMPDIR_TEST}/tail.mp4"
if ffmpeg -v error -f lavfi -i "color=c=blue:s=320x180:d=2" -f lavfi -i "sine=d=4" \
  -c:v mpeg4 -c:a aac -y "$TAIL_VIDEO" 2>/dev/null; then
  TAIL_DIR="${TMPDIR_TEST}/tail"
  assert "audio-longer video extracts" "$VSHOT" "$TAIL_VIDEO" --frames 4 --output "$TAIL_DIR"
  assert_count "tail: 2 frames kept" "$TAIL_DIR" "vshot_*_frame_*.jpg" 2
  assert_count "tail: frame 1 at 0s" "$TAIL_DIR" "vshot_*_frame_0001_t0m00s.jpg" 1
  assert_count "tail: frame 2 at 1s" "$TAIL_DIR" "vshot_*_frame_0002_t0m01s.jpg" 1
  # Seeking past the last video frame: ffmpeg finds no frame → skip with a
  # warning, keep the others, exit 0
  TAIL_AT_DIR="${TMPDIR_TEST}/tail_at"
  if TAIL_AT_ERR=$("$VSHOT" "$TAIL_VIDEO" --at 0.5,1.5,3 --output "$TAIL_AT_DIR" 2>&1 >/dev/null) \
    && echo "$TAIL_AT_ERR" | grep -q "no video frame at or after 3s"; then
    echo "  ✅ --at past the video end: skipped with a warning, exit 0"
    PASS=$((PASS + 1))
  else
    echo "  ❌ --at past the video end: expected exit 0 and a skip warning"
    FAIL=$((FAIL + 1))
  fi
  assert_count "tail --at: 2 frames kept" "$TAIL_AT_DIR" "vshot_*_frame_*.jpg" 2
else
  echo "  ⚠️  audio-longer video: could not generate test clip, skipping"
fi

# Long audio tail in default mode: wide frame spacing takes the seek path,
# times past the 2 s video are skipped
TAIL_LONG="${TMPDIR_TEST}/tail_long.mp4"
if ffmpeg -v error -f lavfi -i "color=c=blue:s=160x90:d=2" -f lavfi -i "sine=d=60" \
  -c:v mpeg4 -c:a aac -y "$TAIL_LONG" 2>/dev/null; then
  TAIL_LONG_DIR="${TMPDIR_TEST}/tail_long"
  if TAIL_LONG_OUT=$("$VSHOT" "$TAIL_LONG" --frames 3 --output "$TAIL_LONG_DIR" 2>&1) \
    && echo "$TAIL_LONG_OUT" | grep -q "seeking to each time"; then
    echo "  ✅ long audio tail: seek path, exit 0"
    PASS=$((PASS + 1))
  else
    echo "  ❌ long audio tail: expected the seek path and exit 0"
    FAIL=$((FAIL + 1))
  fi
  assert_count "long tail: 1 frame kept" "$TAIL_LONG_DIR" "vshot_*_frame_0001_t0m00s.jpg" 1
else
  echo "  ⚠️  long audio tail: could not generate test clip, skipping"
fi

echo ""
echo "── Reported times match frame content (#10) ──"
# Luma encodes the source time: Y = 16 + 10 * T (limited range), so a
# full-range JPEG pixel value v maps back to T = v * 219 / 2550.
IM_CMD=$(command -v magick || command -v convert || true)
# Check every frame of a --json result: reported time within 0.5 s of the
# time encoded in the image
check_content_times() {
  local json="$1" ok=true path time est
  [ -n "$IM_CMD" ] || return 0
  while read -r path time; do
    est=$("$IM_CMD" "$path" -colorspace gray -format '%[fx:mean*255*219/2550]' info: 2>/dev/null)
    if ! awk -v a="$est" -v b="$time" 'BEGIN{d = a - b; if (d < 0) d = -d; exit !(a != "" && d < 0.5)}'; then
      echo "     $path: reported ${time}s, content ${est}s"
      ok=false
    fi
  done < <(echo "$json" | grep -o '"path":"[^"]*","time":[0-9.]*' \
    | sed 's/"path":"\([^"]*\)","time":\([0-9.]*\)/\1 \2/')
  $ok
}
json_times() {
  echo "$1" | grep -o '"time":[0-9.]*' | sed 's/"time"://' | tr '\n' ' '
}
check_times() {
  local name="$1" json="$2" expected="$3" got
  got=$(json_times "$json")
  if [ "$got" = "$expected" ] && check_content_times "$json"; then
    echo "  ✅ $name: ${got}"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $name: expected '${expected}', got '${got}'"
    FAIL=$((FAIL + 1))
  fi
}

# Dense 20 s ramp: even spacing must not drift (the old fps filter picked
# frames ~half a step later than their labels)
RAMP="${TMPDIR_TEST}/ramp.mp4"
ffmpeg -v error -f lavfi -i "nullsrc=s=160x90:r=25:d=20,geq=lum='16+10*T':cb=128:cr=128" \
  -c:v mpeg4 -q:v 2 -y "$RAMP" 2>/dev/null
RAMP_JSON=$("$VSHOT" "$RAMP" --frames 4 --no-timestamps --json --output "${TMPDIR_TEST}/ramp" 2>/dev/null)
check_times "single pass: first frame at or after i*D/N" "$RAMP_JSON" "0.00 5.00 10.00 15.00 "
RAMP_INT_JSON=$("$VSHOT" "$RAMP" --interval 6 --no-timestamps --json --output "${TMPDIR_TEST}/ramp_int" 2>/dev/null)
check_times "--interval: first frame at or after i*N" "$RAMP_INT_JSON" "0.00 6.00 12.00 18.00 "

# Sparse VFR: frames only at 0, 5, 10, 15, 20 s. Requested times that fall
# between frames must report the frame actually returned.
SPARSE="${TMPDIR_TEST}/sparse.mp4"
ffmpeg -v error -f lavfi -i "nullsrc=s=160x90:r=1:d=21,geq=lum='16+10*T':cb=128:cr=128" \
  -vf "select='not(mod(n,5))'" -fps_mode vfr -c:v mpeg4 -q:v 2 -y "$SPARSE" 2>/dev/null
SPARSE_JSON=$("$VSHOT" "$SPARSE" --frames 10 --no-timestamps --json --output "${TMPDIR_TEST}/sparse" 2>/dev/null)
check_times "sparse, single pass" "$SPARSE_JSON" "0.00 5.00 10.00 15.00 20.00 "
SPARSE_SEEK_JSON=$("$VSHOT" "$SPARSE" --frames 2 --no-timestamps --json --output "${TMPDIR_TEST}/sparse_seek" 2>/dev/null)
check_times "sparse, seek path (default mode)" "$SPARSE_SEEK_JSON" "0.00 15.00 "
SPARSE_AT_JSON=$("$VSHOT" "$SPARSE" --at 2.1,7,8 --no-timestamps --json --output "${TMPDIR_TEST}/sparse_at" 2>/dev/null)
check_times "sparse --at 2.1,7,8 (duplicate dropped)" "$SPARSE_AT_JSON" "5.00 10.00 "
assert_count "sparse --at: filename has the real time" "${TMPDIR_TEST}/sparse_at" "vshot_*_frame_0001_t0m05s.jpg" 1

echo ""
echo "── ffmpeg errors stay fatal (#10) ──"
# ffmpeg shim: the 2nd seek fails with a genuine error after the 1st succeeded
FF_SHIM_DIR="${TMPDIR_TEST}/ff_shim"
mkdir -p "$FF_SHIM_DIR"
REAL_FFMPEG=$(command -v ffmpeg)
cat > "${FF_SHIM_DIR}/ffmpeg" <<SHIM
#!/bin/bash
case " \$* " in
  *" -ss "*)
    n=\$(( \$(cat "${FF_SHIM_DIR}/count" 2>/dev/null || echo 0) + 1 ))
    echo "\$n" > "${FF_SHIM_DIR}/count"
    if [ "\$n" -eq 2 ]; then
      echo "simulated ffmpeg failure" >&2
      exit 1
    fi ;;
esac
exec "$REAL_FFMPEG" "\$@"
SHIM
chmod +x "${FF_SHIM_DIR}/ffmpeg"
for args in "--at 0.5,1.5,2.5" "--frames 2"; do
  rm -f "${FF_SHIM_DIR}/count"
  # shellcheck disable=SC2086
  if FF_ERR=$(PATH="${FF_SHIM_DIR}:$PATH" "$VSHOT" "$SPARSE" $args --output "${TMPDIR_TEST}/ff_fail" 2>&1 >/dev/null); then
    echo "  ❌ $args: error after a successful frame must fail (got exit 0)"
    FAIL=$((FAIL + 1))
  elif echo "$FF_ERR" | grep -q "simulated ffmpeg failure"; then
    echo "  ✅ $args: error after a successful frame is fatal and printed"
    PASS=$((PASS + 1))
  else
    echo "  ❌ $args: ffmpeg diagnostic not printed"
    FAIL=$((FAIL + 1))
  fi
done

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
echo "── Montage timestamp labels (#11) ──"
# --montage --cleanup: no per-frame burn-in, timestamps become cell labels
if LBL_OUT=$("$VSHOT" "$VIDEO" --montage --cleanup --frames 3 --output "${TMPDIR_TEST}/lbl" 2>&1) \
  && ! echo "$LBL_OUT" | grep -q "Adding timestamps"; then
  echo "  ✅ --montage --cleanup skips per-frame burn-in"
  PASS=$((PASS + 1))
else
  echo "  ❌ --montage --cleanup still burns in per frame: $LBL_OUT"
  FAIL=$((FAIL + 1))
fi
# Without --cleanup frames are kept, so they still get burned-in timestamps
if KEEP_OUT=$("$VSHOT" "$VIDEO" --montage --frames 3 --output "${TMPDIR_TEST}/lbl_keep" 2>&1) \
  && echo "$KEEP_OUT" | grep -q "Adding timestamps"; then
  echo "  ✅ --montage without --cleanup keeps per-frame burn-in"
  PASS=$((PASS + 1))
else
  echo "  ❌ --montage without --cleanup skipped burn-in: $KEEP_OUT"
  FAIL=$((FAIL + 1))
fi
# Labels add a caption row under each cell, so the montage is taller than
# the --no-timestamps one (which must have no labels)
assert "--no-timestamps --montage --cleanup" "$VSHOT" "$VIDEO" --no-timestamps --montage --cleanup --frames 3 --output "${TMPDIR_TEST}/lbl_none"
H_LBL=$(identify -format '%h' "${TMPDIR_TEST}"/lbl/*_montage_*.jpg 2>/dev/null)
H_NONE=$(identify -format '%h' "${TMPDIR_TEST}"/lbl_none/*_montage_*.jpg 2>/dev/null)
if [ -n "$H_LBL" ] && [ -n "$H_NONE" ] && [ "$H_LBL" -gt "$H_NONE" ]; then
  echo "  ✅ labels rendered; --no-timestamps disables them (${H_LBL}px > ${H_NONE}px)"
  PASS=$((PASS + 1))
else
  echo "  ❌ label height check (labels=${H_LBL:-?}px, none=${H_NONE:-?}px)"
  FAIL=$((FAIL + 1))
fi
# Label failure: montage shim that rejects -label → montage still created
# without labels, with a warning on stderr
REAL_MONTAGE_BIN=$(command -v montage)
if [ -n "$REAL_MONTAGE_BIN" ]; then
  SHIM_DIR="${TMPDIR_TEST}/shim"
  mkdir -p "$SHIM_DIR"
  cat > "${SHIM_DIR}/montage" <<SHIM
#!/bin/bash
for a in "\$@"; do [ "\$a" = "-label" ] && { echo "shim: label rejected" >&2; exit 1; }; done
exec "$REAL_MONTAGE_BIN" "\$@"
SHIM
  chmod +x "${SHIM_DIR}/montage"
  if NOLBL_OUT=$(PATH="${SHIM_DIR}:$PATH" "$VSHOT" "$VIDEO" --montage --cleanup --frames 3 --output "${TMPDIR_TEST}/lbl_fail" 2>&1) \
    && echo "$NOLBL_OUT" | grep -q "Timestamp labels failed"; then
    echo "  ✅ label failure falls back to montage without labels"
    PASS=$((PASS + 1))
  else
    echo "  ❌ label failure fallback: $NOLBL_OUT"
    FAIL=$((FAIL + 1))
  fi
  assert_count "label fallback: montage exists" "${TMPDIR_TEST}/lbl_fail" "*_montage_*.jpg" 1
  assert_count "label fallback: frames kept despite --cleanup" "${TMPDIR_TEST}/lbl_fail" "vshot_*_frame_*_t*.jpg" 3
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

# Out-of-range --scene threshold gives a clear error, not "multiple video files" (#9)
for BAD_SCENE in 1.5 -0.1 2; do
  SCENE_ERR=$("$VSHOT" "$SCENE_VIDEO" --scene "$BAD_SCENE" --output "${TMPDIR_TEST}/scene_bad" 2>&1 >/dev/null)
  if [ $? -ne 0 ] && echo "$SCENE_ERR" | grep -q "threshold must be"; then
    echo "  ✅ scene threshold $BAD_SCENE rejected with clear error"
    PASS=$((PASS + 1))
  else
    echo "  ❌ scene threshold $BAD_SCENE: unexpected result: $SCENE_ERR"
    FAIL=$((FAIL + 1))
  fi
done

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
echo "── Scene frame cap (--max-frames) ──"
# 60 s video with a hard cut every second → 59 scene changes, the Nth at N s
CUTS_VIDEO="${TMPDIR_TEST}/cuts.mp4"
CUTS_SRC="nullsrc=s=640x360:r=10:d=60,geq=lum='if(mod(floor(T),2),230,20)':cb=128:cr=128"
ffmpeg -v error -f lavfi -i "$CUTS_SRC" -c:v libx264 -pix_fmt yuv420p -y "$CUTS_VIDEO" 2>/dev/null || \
  ffmpeg -v error -f lavfi -i "$CUTS_SRC" -c:v mpeg4 -pix_fmt yuv420p -y "$CUTS_VIDEO" 2>/dev/null

# Each kept frame's original index (scene N = cut at N s) must match the
# timestamp in its filename, and timestamps must strictly increase
check_cut_timestamps() {
  local dir="$1" prev=-1 f idx secs
  for f in "$dir"/vshot_*_frame_*_t*.jpg; do
    [ -f "$f" ] || return 1
    idx="${f##*_frame_}"
    idx=$((10#${idx%%_t*}))
    secs=$(echo "$f" | sed 's/.*_t\([0-9]*\)m\([0-9.]*\)s\.jpg$/\1 \2/' | awk '{printf "%d", $1 * 60 + $2}')
    [ "$idx" -eq "$secs" ] || return 1
    [ "$secs" -gt "$prev" ] || return 1
    prev=$secs
  done
}

CAP_DEFAULT_DIR="${TMPDIR_TEST}/cap_default"
CAP_ERR=$("$VSHOT" "$CUTS_VIDEO" --scene --output "$CAP_DEFAULT_DIR" 2>&1 >/dev/null)
assert_count "default cap: 30 frames" "$CAP_DEFAULT_DIR" "vshot_*_frame_*.jpg" 30
if echo "$CAP_ERR" | grep -q "59 scene changes detected"; then
  echo "  ✅ cap warning on stderr reports original count"
  PASS=$((PASS + 1))
else
  echo "  ❌ cap warning missing: $CAP_ERR"
  FAIL=$((FAIL + 1))
fi
assert "default cap: timestamps aligned and increasing" check_cut_timestamps "$CAP_DEFAULT_DIR"

CAP_DIR="${TMPDIR_TEST}/cap"
assert "--max-frames 5 + montage" "$VSHOT" "$CUTS_VIDEO" --scene --max-frames 5 --montage --output "$CAP_DIR"
assert_count "--max-frames 5: 5 frames" "$CAP_DIR" "vshot_*_frame_*.jpg" 5
assert "--max-frames 5: timestamps aligned and increasing" check_cut_timestamps "$CAP_DIR"
assert_count "--max-frames 5: montage exists" "$CAP_DIR" "*_montage_*.jpg" 1

# Uneven cuts: dense every second for 1–10 s, then sparse at 30 s and 50 s.
# Thinning must space by time, not by scene index, so 30 s and 50 s survive.
UNEVEN_VIDEO="${TMPDIR_TEST}/uneven.mp4"
UNEVEN_SRC="nullsrc=s=640x360:r=10:d=60,geq=lum='if(mod(if(lt(T,11),floor(T),if(lt(T,30),10,if(lt(T,50),11,12))),2),230,20)':cb=128:cr=128"
ffmpeg -v error -f lavfi -i "$UNEVEN_SRC" -c:v libx264 -pix_fmt yuv420p -y "$UNEVEN_VIDEO" 2>/dev/null || \
  ffmpeg -v error -f lavfi -i "$UNEVEN_SRC" -c:v mpeg4 -pix_fmt yuv420p -y "$UNEVEN_VIDEO" 2>/dev/null

# Kept frames' timestamps (whole seconds), space-separated, from filenames
kept_seconds() {
  local f
  for f in "$1"/vshot_*_frame_*_t*.jpg; do
    [ -f "$f" ] || continue
    echo "$f" | sed 's/.*_t\([0-9]*\)m\([0-9.]*\)s\.jpg$/\1 \2/' | awk '{printf "%d ", $1 * 60 + $2 + 0.5}'
  done
}

UNEVEN_DIR="${TMPDIR_TEST}/uneven"
UNEVEN_ERR=$("$VSHOT" "$UNEVEN_VIDEO" --scene --max-frames 5 --output "$UNEVEN_DIR" 2>&1 >/dev/null)
assert_count "uneven cuts --max-frames 5: 5 frames" "$UNEVEN_DIR" "vshot_*_frame_*.jpg" 5
UNEVEN_KEPT=" $(kept_seconds "$UNEVEN_DIR")"
if echo "$UNEVEN_ERR" | grep -q "12 scene changes detected" && \
   echo "$UNEVEN_KEPT" | grep -q " 30 " && echo "$UNEVEN_KEPT" | grep -q " 50 "; then
  echo "  ✅ uneven cuts: sparse later scenes (30 s, 50 s) kept"
  PASS=$((PASS + 1))
else
  echo "  ❌ uneven cuts: kept [${UNEVEN_KEPT}], stderr: $UNEVEN_ERR"
  FAIL=$((FAIL + 1))
fi

# Leading-zero cap must be normalized to decimal (no octal, valid JSON)
OCT_DIR="${TMPDIR_TEST}/cap_octal"
OCT_OUT=$("$VSHOT" "$CUTS_VIDEO" --scene --max-frames 08 --montage --json --output "$OCT_DIR" 2>/dev/null)
OCT_RC=$?
if command -v python3 >/dev/null 2>&1; then
  OCT_FRAMES=$(echo "$OCT_OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["frames"])' 2>/dev/null)
else
  OCT_FRAMES=$(echo "$OCT_OUT" | grep -o '"frames":[0-9]*' | sed 's/"frames"://')
  echo "$OCT_OUT" | grep -q '"frames":0[0-9]' && OCT_FRAMES="invalid"
fi
if [ "$OCT_RC" -eq 0 ] && [ "$OCT_FRAMES" = "8" ]; then
  echo "  ✅ --max-frames 08 --json: valid JSON with frames 8"
  PASS=$((PASS + 1))
else
  echo "  ❌ --max-frames 08 --json: rc=$OCT_RC frames='$OCT_FRAMES' out: $OCT_OUT"
  FAIL=$((FAIL + 1))
fi
assert_count "--max-frames 08: 8 frames" "$OCT_DIR" "vshot_*_frame_*.jpg" 8

assert_fail "invalid --max-frames 0 errors" "$VSHOT" "$CUTS_VIDEO" --scene --max-frames 0
assert_fail "invalid --max-frames abc errors" "$VSHOT" "$CUTS_VIDEO" --scene --max-frames abc

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
if [ -z "$(find "$NAME_STALE_DIR" -maxdepth 1 -name '.vshot_montage_*' 2>/dev/null)" ]; then
  echo "  ✅ --name: no temp montage left after failed run"
  PASS=$((PASS + 1))
else
  echo "  ❌ --name: temp montage file left behind"
  FAIL=$((FAIL + 1))
fi
# ImageMagick filename templates (%d, [..]) must be written literally
NAME_TPL_DIR="${TMPDIR_TEST}/name_tpl"
assert "--name 'review%03d'" "$VSHOT" "$VIDEO" --montage --cleanup --frames 2 --name 'review%03d' --output "$NAME_TPL_DIR"
assert_nonempty "--name 'review%03d' -> review%03d.jpg" "${NAME_TPL_DIR}/review%03d.jpg"
if [ ! -e "${NAME_TPL_DIR}/review000.jpg" ]; then
  echo "  ✅ --name: no template-expanded review000.jpg"
  PASS=$((PASS + 1))
else
  echo "  ❌ --name: ImageMagick expanded the template to review000.jpg"
  FAIL=$((FAIL + 1))
fi
assert "--name 'shot[1]'" "$VSHOT" "$VIDEO" --montage --cleanup --frames 2 --name 'shot[1]' --output "$NAME_TPL_DIR"
assert_nonempty "--name 'shot[1]' -> shot[1].jpg" "${NAME_TPL_DIR}/shot[1].jpg"
assert_count "--name templates: exactly 2 montages, no temp leftovers" "$NAME_TPL_DIR" "*.jpg" 2
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

echo "── Montage max edge (--max-edge, #3) ──"
# 20 frames in detail mode → 5x4 grid of 1280x720 cells (6440 px wide unbounded).
# --at is not capped to the 3s duration, so it can request 20 frames.
EDGE_AT="0,0.15,0.3,0.45,0.6,0.75,0.9,1.05,1.2,1.35,1.5,1.65,1.8,1.95,2.1,2.25,2.4,2.55,2.7,2.85"
montage_long_edge() {
  local m
  m=$(find "$1" -maxdepth 1 -name "*_montage_*.jpg" -type f 2>/dev/null | head -1)
  [ -n "$m" ] || { echo 0; return; }
  ffprobe -v error -show_entries stream=width,height -of csv=p=0 "$m" \
    | awk -F, '{print ($1 > $2) ? $1 : $2}'
}
EDGE_DIR="${TMPDIR_TEST}/max_edge"
EDGE_ERR="${TMPDIR_TEST}/max_edge.err"
"$VSHOT" "$VIDEO" --at "$EDGE_AT" --mode detail --montage --output "$EDGE_DIR" >/dev/null 2>"$EDGE_ERR"
EDGE=$(montage_long_edge "$EDGE_DIR")
if [ "$EDGE" -gt 0 ] && [ "$EDGE" -le 2576 ]; then
  echo "  ✅ default montage long edge <= 2576 (${EDGE}px)"
  PASS=$((PASS + 1))
else
  echo "  ❌ default montage long edge ${EDGE}px (expected 1-2576)"
  FAIL=$((FAIL + 1))
fi
assert "shrink note on stderr" grep -q "cells shrunk" "$EDGE_ERR"
NOEDGE_DIR="${TMPDIR_TEST}/max_edge_off"
"$VSHOT" "$VIDEO" --at "$EDGE_AT" --mode detail --montage --max-edge 0 --output "$NOEDGE_DIR" >/dev/null 2>&1
EDGE=$(montage_long_edge "$NOEDGE_DIR")
if [ "$EDGE" -eq 6440 ]; then
  echo "  ✅ --max-edge 0 keeps full size (${EDGE}px)"
  PASS=$((PASS + 1))
else
  echo "  ❌ --max-edge 0 long edge ${EDGE}px (expected 6440)"
  FAIL=$((FAIL + 1))
fi
EDGE_JSON=$("$VSHOT" "$VIDEO" --at "$EDGE_AT" --mode detail --montage --json --output "${TMPDIR_TEST}/max_edge_json" 2>/dev/null)
if echo "$EDGE_JSON" | grep -q '"montage_cell":"[0-9]*x[0-9]*","montage_shrunk":true'; then
  echo "  ✅ --json reports montage_cell / montage_shrunk"
  PASS=$((PASS + 1))
else
  echo "  ❌ --json missing montage_cell / montage_shrunk: $EDGE_JSON"
  FAIL=$((FAIL + 1))
fi
# A cap below the smallest padded 5x4 grid must fail instead of overshooting
TINY_ERR="${TMPDIR_TEST}/max_edge_tiny.err"
assert_fail "--max-edge 40 (below grid minimum) fails" \
  "$VSHOT" "$VIDEO" --at "$EDGE_AT" --mode detail --montage --max-edge 40 --output "${TMPDIR_TEST}/max_edge_tiny"
"$VSHOT" "$VIDEO" --at "$EDGE_AT" --mode detail --montage --max-edge 40 --output "${TMPDIR_TEST}/max_edge_tiny2" >/dev/null 2>"$TINY_ERR"
assert "too-small cap names the minimum" grep -q "too small .*minimum [0-9]" "$TINY_ERR"
# Leading zeros are decimal, not octal
"$VSHOT" "$VIDEO" --at "$EDGE_AT" --mode detail --montage --max-edge 2576 --output "${TMPDIR_TEST}/max_edge_dec" >/dev/null 2>&1
"$VSHOT" "$VIDEO" --at "$EDGE_AT" --mode detail --montage --max-edge 02576 --output "${TMPDIR_TEST}/max_edge_oct" >/dev/null 2>&1
EDGE_DEC=$(montage_long_edge "${TMPDIR_TEST}/max_edge_dec")
EDGE_OCT=$(montage_long_edge "${TMPDIR_TEST}/max_edge_oct")
if [ "$EDGE_OCT" -gt 0 ] && [ "$EDGE_OCT" -le 2576 ] && [ "$EDGE_OCT" -eq "$EDGE_DEC" ]; then
  echo "  ✅ --max-edge 02576 is decimal (${EDGE_OCT}px, same as 2576)"
  PASS=$((PASS + 1))
else
  echo "  ❌ --max-edge 02576 long edge ${EDGE_OCT}px (2576 gives ${EDGE_DEC}px)"
  FAIL=$((FAIL + 1))
fi
assert "--max-edge 0800 succeeds" \
  "$VSHOT" "$VIDEO" --at "$EDGE_AT" --mode detail --montage --max-edge 0800 --output "${TMPDIR_TEST}/max_edge_0800"

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
JSON_TIMES=$(echo "$JSON_OUT" | grep -o '"time":[0-9.]*' | tr '\n' ' ')
# 25 fps: the first frame at or after 1.5 s is at 1.52 s (real frame time)
if [ "$JSON_TIMES" = '"time":0.00 "time":1.52 ' ]; then
  echo "  ✅ --json times are the real frame times (0.00, 1.52)"
  PASS=$((PASS + 1))
else
  echo "  ❌ --json times unexpected: $JSON_TIMES"
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
assert_fail "invalid --max-edge errors" "$VSHOT" "$VIDEO" --montage --max-edge -1 --frames 2

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
