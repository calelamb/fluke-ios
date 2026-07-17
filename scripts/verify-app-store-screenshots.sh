#!/usr/bin/env bash

set -euo pipefail

if (($# != 1)); then
  printf 'Usage: %s <screenshot-directory>\n' "$0" >&2
  exit 2
fi

screenshot_directory="$1"
test -d "$screenshot_directory" || {
  printf 'Screenshot directory does not exist: %s\n' "$screenshot_directory" >&2
  exit 1
}

shopt -s nullglob
screenshots=("$screenshot_directory"/*.png "$screenshot_directory"/*.jpg "$screenshot_directory"/*.jpeg)
if ((${#screenshots[@]} < 1 || ${#screenshots[@]} > 10)); then
  echo "App Store screenshot set must contain between 1 and 10 images" >&2
  exit 1
fi

expected_dimensions=""
inspection_root="$(mktemp -d "${TMPDIR:-/tmp}/fluke-screenshot-inspection.XXXXXX")"
trap 'rm -rf "$inspection_root"' EXIT
for screenshot in "${screenshots[@]}"; do
  width="$(sips -g pixelWidth "$screenshot" | awk '/pixelWidth/{print $2}')"
  height="$(sips -g pixelHeight "$screenshot" | awk '/pixelHeight/{print $2}')"
  dimensions="${width}x${height}"
  case "$dimensions" in
    1260x2736|2736x1260|1290x2796|2796x1290|1320x2868|2868x1320) ;;
    *)
      printf 'unsupported iPhone screenshot size: %s (%s)\n' "$screenshot" "$dimensions" >&2
      exit 1
      ;;
  esac
  if [[ -z "$expected_dimensions" ]]; then
    expected_dimensions="$dimensions"
  elif [[ "$expected_dimensions" != "$dimensions" ]]; then
    echo "App Store screenshots must use one consistent 6.9-inch size and orientation" >&2
    exit 1
  fi

  inspection_image="$inspection_root/$(printf '%04d' "$RANDOM").bmp"
  sips -Z 120 -s format bmp "$screenshot" --out "$inspection_image" >/dev/null
  if ! python3 - "$inspection_image" <<'PY'
import struct
import sys

data = open(sys.argv[1], "rb").read()
pixel_offset = struct.unpack_from("<I", data, 10)[0]
width, signed_height, planes, bits_per_pixel = struct.unpack_from("<iiHH", data, 18)
if planes != 1 or bits_per_pixel != 24 or width <= 0 or signed_height == 0:
    raise SystemExit("unsupported inspection bitmap")
height = abs(signed_height)
row_stride = ((width * 3 + 3) // 4) * 4
minimum_band_rows = max(3, round(height * 0.05))
consecutive_dark_rows = 0
for row_index in range(height):
    row_start = pixel_offset + row_index * row_stride
    dark_pixels = 0
    for column in range(width):
        blue, green, red = data[row_start + column * 3:row_start + column * 3 + 3]
        if max(red, green, blue) <= 20:
            dark_pixels += 1
    if dark_pixels / width >= 0.80:
        consecutive_dark_rows += 1
        if consecutive_dark_rows >= minimum_band_rows:
            raise SystemExit(1)
    else:
        consecutive_dark_rows = 0
PY
  then
    printf 'screenshot contains an excessive near-black band: %s\n' "$screenshot" >&2
    exit 1
  fi
done

printf 'Validated %d App Store screenshot(s) at %s\n' "${#screenshots[@]}" "$expected_dimensions"
