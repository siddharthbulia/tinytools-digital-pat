#!/usr/bin/env bash
# Generate the "anay" character — a buff, swaggy, handsome chibi heartthrob — from a local photo.
# Full sprite set (10 poses + 6 per-mood blinks), front-facing enforced, resumable (skips existing).
set -uo pipefail

KEY=$(grep -o 'sk-[A-Za-z0-9_-]*' ~/.gstack/openai.json | head -1)
OUT=/Users/siddharthbulia/Code/app-factory/apps/digital-pat/characters/anay
RAW=~/.gstack/projects/digital-pat/people/anay
PHOTO_SRC="/Users/siddharthbulia/Downloads/E96E553C-EB80-4774-9197-166196780B4E.JPG"
MAX=4
mkdir -p "$OUT" "$RAW"

FRONT="The mascot MUST FACE THE VIEWER HEAD-ON — a front-facing, forward-looking, upright, centered pose looking straight at the camera — NO MATTER how the source photo is angled, turned, or cropped."
BASE="Turn this person into an ADORABLE chibi pixel-art mascot, cute retro Tamagotchi style. $FRONT Huge round head about 55% of the body, big sparkly low-set eyes with white catchlights, and a confident, cool, SWAGGY little smirk. Give him a BUFF muscular build — broad shoulders and a fit chest, like a handsome bodybuilder heartthrob / chick-magnet — but keep it cute and chibi. Tiny rounded muscular body sitting upright with confident swagger, thick clean outline, soft warm palette, transparent background, single centered character. Keep his most recognizable features: short spiky black hair, a full short black beard with a soul-patch/goatee, warm medium skin tone, a thin gold chain necklace, and a light grey crewneck sweatshirt."
PRE="Keep this EXACT chibi pixel character identical — same buff swaggy face, same hair/beard, same gold chain, same FRONT-FACING forward pose, same proportions and pixel-art style, transparent background. Change ONLY: "
BLINKPRE="Keep this EXACT chibi pixel character identical — same outfit, same hair/beard/headwear, same front-facing pose, same everything. Change ONLY: both eyes gently closed in a soft blink. Transparent background, single centered character."

MOODS=(
"coding|add small round eyeglasses and a cozy focused look (keep the swagger)"
"thinking|add small round glasses and a little glowing yellow lightbulb floating above the head"
"meeting|wearing a smart dark blazer over the build, sitting up attentively and confident"
"communicating|wearing small headphones with a tiny speech bubble floating beside the head"
"browsing|holding a tiny smartphone in both hands, looking at it coolly"
"creating|holding a tiny paintbrush and a small artist palette"
"vibing|wearing big headphones, eyes happily closed, a small music note floating, cool vibe"
"idle|eyes closed and head gently drooping, sleepy resting pose, small Zzz floating"
"pat|eyes happily closed in upward curved arcs, big rosy blush on the cheeks, a content smile"
"blink|both eyes gently closed in a soft blink, content cool look"
)
BLINKMOODS=(coding thinking meeting communicating browsing creating)

edit () {  # $1 in $2 prompt $3 out
  local i
  for i in 1 2 3; do
    curl -s https://api.openai.com/v1/images/edits \
      -H "Authorization: Bearer $KEY" -F model=gpt-image-1 -F image="@$1;type=image/png" \
      -F size=1024x1024 -F quality=medium -F background=transparent -F n=1 -F prompt="$2" \
      | python3 -c "import sys,json,base64; d=json.load(sys.stdin); open('$3','wb').write(base64.b64decode(d['data'][0]['b64_json']))" 2>/dev/null \
      && [ -s "$3" ] && return 0
    sleep 5
  done
  return 1
}
pixelate () {  # $1 raw $2 out $3 palette(optional)
  if [ -n "${3:-}" ]; then
    magick "$1" -background none -resize 64x64 -channel A -threshold 45% +channel -remap "$3" -dither None -scale 512x512 "$2"
  else
    magick "$1" -background none -resize 64x64 -channel A -threshold 45% +channel -colors 24 -dither None -scale 512x512 "$2"
  fi
}

# 0) normalize photo
[ -s "$RAW/photo.png" ] || magick "$PHOTO_SRC" "$RAW/photo.png"

# 1) base / neutral (must exist first — it's the palette for everything else)
if [ ! -s "$OUT/neutral.png" ]; then
  echo ">> base…"
  [ -s "$RAW/base.png" ] || edit "$RAW/photo.png" "$BASE" "$RAW/base.png" || { echo "BASE FAILED"; exit 1; }
  pixelate "$RAW/base.png" "$OUT/neutral.png"
  echo ">> neutral done"
fi

# 2) moods (parallel, from base.png)
for m in "${MOODS[@]}"; do
  name="${m%%|*}"; detail="${m#*|}"
  [ -s "$OUT/$name.png" ] && continue
  (
    if edit "$RAW/base.png" "$PRE $detail" "$RAW/$name.png"; then
      pixelate "$RAW/$name.png" "$OUT/$name.png" "$OUT/neutral.png"; echo ">> $name ok"
    else echo ">> $name FAILED"; fi
  ) &
  while [ "$(jobs -r | wc -l)" -ge "$MAX" ]; do sleep 2; done
done
wait

# 3) per-mood blinks (parallel, from each raw mood png)
for m in "${BLINKMOODS[@]}"; do
  out="$OUT/$m-blink.png"
  [ -s "$out" ] && continue
  [ -s "$RAW/$m.png" ] || { echo ">> no raw $m for blink"; continue; }
  (
    if edit "$RAW/$m.png" "$BLINKPRE" "$RAW/$m-blink.png"; then
      pixelate "$RAW/$m-blink.png" "$out" "$OUT/neutral.png"; echo ">> $m-blink ok"
    else echo ">> $m-blink FAILED"; fi
  ) &
  while [ "$(jobs -r | wc -l)" -ge "$MAX" ]; do sleep 2; done
done
wait

echo "DONE anay: $(ls "$OUT" | wc -l | tr -d ' ') sprites"
ls "$OUT"