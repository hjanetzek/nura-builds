#!/bin/sh
# A photo of the Samsung Galaxy S III Neo's screen from a camera pointed at it: the "Android IP
# Camera" app (github.com/DigitallyRefined/android-ip-camera) on another phone, its snapshot
# endpoint. Saves the full image and a scaled copy (auto-oriented) for viewing.
#
# Usage: tools/s3ve3g-screenshot.sh [NAME]
#   NAME  file name stem (default: screen-<time>)
# Environment: CAM (default https://192.168.178.58:4444), CAM_USER/CAM_PASS (if the app has
# authentication on), OUT (default ./out/s3ve3g/screens), SIZE (scaled copy, default 900)
set -eu

CAM=${CAM:-https://192.168.178.58:4444}
OUT=${OUT:-$(cd "$(dirname "$0")/.." && pwd)/out/s3ve3g/screens}
SIZE=${SIZE:-900}
name=${1:-screen-$(date +%Y%m%d-%H%M%S)}
mkdir -p "$OUT"

auth=
[ -n "${CAM_USER:-}" ] && auth="-u $CAM_USER:${CAM_PASS:-}"
# shellcheck disable=SC2086 # optional auth
code=$(curl -sk -m 20 $auth -o "$OUT/$name.jpg" -w "%{http_code} %{content_type}" "$CAM/video/snapshot")
case "$code" in
200\ image/*) ;;
*)
	echo "camera: $code: $(head -c 200 "$OUT/$name.jpg" 2>/dev/null)" >&2
	rm -f "$OUT/$name.jpg"
	exit 1
	;;
esac

python3 - "$OUT/$name.jpg" "$OUT/$name-small.jpg" "$SIZE" <<'PY'
import sys
from PIL import Image, ImageOps
im = ImageOps.exif_transpose(Image.open(sys.argv[1]))
im.thumbnail((int(sys.argv[3]), int(sys.argv[3])))
im.save(sys.argv[2], quality=85)
PY
echo "$OUT/$name-small.jpg"
