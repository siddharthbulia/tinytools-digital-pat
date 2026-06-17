#!/usr/bin/env bash
# Generate animation frames for the kitten, consistent with the hero sprite,
# via gpt-image-1 image-edits (character consistency) + ImageMagick pixelate/remap.
set -uo pipefail

KEY=$(grep -o 'sk-[A-Za-z0-9_-]*' ~/.gstack/openai.json | head -1)
REF=~/.gstack/projects/digital-pat/designs/kitten-styles-20260613/pixA.png        # raw hero reference
HERO64=/Users/siddharthbulia/Code/app-factory/apps/digital-pat/design/concepts/pixel/pixA-64.png  # palette
RAW=~/.gstack/projects/digital-pat/designs/kitten-styles-20260613/frames
OUT=/Users/siddharthbulia/Code/app-factory/apps/digital-pat/sprites
mkdir -p "$RAW"

PRE="Keep this EXACT adorable pixel-art kitten: same cream and peach fur, same big sparkly eyes, same retro Tamagotchi pixel style, same proportions, transparent background. Change ONLY:"

declare -a FRAMES=(
  "blink|both eyes gently closed in happy upward curved arcs, content tiny smile, sitting (a blink frame)"
  "walk1|standing on all fours and lifting its LEFT front paw up mid-step, a cute little walking pose, slight forward lean"
  "walk2|standing on all fours and lifting its RIGHT front paw up mid-step, a cute little walking pose, slight forward lean"
  "walkside1|shown in SIDE PROFILE facing RIGHT, walking, front-right leg reaching forward and back-left leg pushing off, tail up for balance"
  "walkside2|shown in SIDE PROFILE facing RIGHT, walking, opposite stride: other legs swapped, mid-trot, tail up"
)

one () {
  local name="$1" detail="$2" tmp="$RAW/$1.png"
  echo ">> $name"
  curl -s https://api.openai.com/v1/images/edits \
    -H "Authorization: Bearer $KEY" \
    -F model=gpt-image-1 -F image="@$REF" \
    -F size=1024x1024 -F quality=medium -F background=transparent -F n=1 \
    -F prompt="$PRE $detail" \
    | python3 -c "import sys,json,base64; d=json.load(sys.stdin); open('$tmp','wb').write(base64.b64decode(d['data'][0]['b64_json'])); print('   raw ok')" \
    || { echo "   FAILED $name"; return 1; }
  magick "$tmp" -background none -resize 64x64 -channel A -threshold 45% +channel \
    -remap "$HERO64" -dither None -scale 512x512 "$OUT/$name.png"
  echo "   pixel ok -> $OUT/$name.png"
}

for f in "${FRAMES[@]}"; do one "${f%%|*}" "${f#*|}"; done
echo "ALL DONE"
ls -1 "$OUT" | tr '\n' ' '; echo
