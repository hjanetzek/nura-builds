#!/bin/sh
# A photo of the Samsung Galaxy S III Neo's screen from a camera pointed at it: the "Android IP
# Camera" app (github.com/DigitallyRefined/android-ip-camera) on another phone, its snapshot
# MJPEG stream (the snapshot endpoint can be stale). Saves the frame and a scaled copy
# (auto-oriented) for viewing.
#
# Usage: tools/s3ve3g-screenshot.sh [NAME]
#   NAME  file name stem (default: screen-<time>)
# Environment: CAM (default https://192.168.178.87:4444), CAM_USER/CAM_PASS (if the app has
# authentication on), OUT (default ./out/s3ve3g/screens), SIZE (scaled copy, default 900),
# STREAM_S (seconds of stream to read, default 3), ROTATE (degrees counterclockwise, default -90)
set -eu

CAM=${CAM:-https://192.168.178.87:4444}
OUT=${OUT:-$(cd "$(dirname "$0")/.." && pwd)/out/s3ve3g/screens}
SIZE=${SIZE:-900}
name=${1:-screen-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$OUT"

auth=
[ -n "${CAM_USER:-}" ] && auth="-u $CAM_USER:${CAM_PASS:-}"
# The current frame from the MJPEG stream (the app's /video/snapshot can return a stale picture):
# read the stream for STREAM_S seconds, keep the last complete JPEG
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
# shellcheck disable=SC2086 # optional auth
curl -sk -m "${STREAM_S:-3}" $auth -o "$tmp" "$CAM/video/mjpeg" || true
python3 - "$tmp" "$OUT/$name.jpg" <<'PY2' || { echo "camera: no frame from $CAM/video/mjpeg: $(head -c 200 "$tmp")" >&2; exit 1; }
import sys
d = open(sys.argv[1], 'rb').read()
end = d.rfind(b'\xff\xd9')
start = d.rfind(b'\xff\xd8\xff', 0, end)
if start < 0 or end < 0:
    sys.exit(1)
open(sys.argv[2], 'wb').write(d[start:end + 2])
PY2

python3 - "$OUT/$name.jpg" "$OUT/$name-small.jpg" "$SIZE" "${ROTATE:--90}" <<'PY'
import sys
from PIL import Image, ImageOps
im = ImageOps.exif_transpose(Image.open(sys.argv[1]))
# the stream's frames are the sensor's landscape (no EXIF orientation)
if int(sys.argv[4]):
    im = im.rotate(int(sys.argv[4]), expand=True)
    im.save(sys.argv[1], quality=92)
im.thumbnail((int(sys.argv[3]), int(sys.argv[3])))
im.save(sys.argv[2], quality=85)
PY
echo "$OUT/$name-small.jpg"
