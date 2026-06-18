#!/usr/bin/env bash
# Generate the "shreya" character from a local photo. Full sprite set (10 poses + 6 per-mood blinks),
# front-facing enforced, resumable. Same pipeline as gen-shikhar.sh.
set -uo pipefail

KEY=$(grep -o 'sk-[A-Za-z0-9_-]*' ~/.gstack/openai.json | head -1)
OUT=/Users/siddharthbulia/Code/app-factory/apps/digital-pat/characters/shreya
RAW=~/.gstack/projects/digital-pat/people/shreya
PHOTO_SRC="/Users/siddharthbulia/.claude/image-cache/510989db-9381-4db2-9f1c-3ce84b976b88/20.png"
MAX=4
mkdir -p "$OUT" "$RAW"

FRONT="The mascot MUST FACE THE VIEWER HEAD-ON — a front-facing, forward-looking, upright, centered pose looking straight at the camera — NO MATTER how the source photo is angled, turned, or cropped."
BASE="Turn this person into an ADORABLE chibi pixel-art mascot, cute retro Tamagotchi style. $FRONT Huge round head about 60% of the body, big sparkly low-set eyes with white catchlights behind her big glasses, and a warm, friendly little smile. Tiny rounded body sitting upright, thick clean outline, soft warm palette, transparent background, single centered character. Keep her most recognizable features: LARGE SQUARE geometric eyeglasses with tortoiseshell-and-gold frames, dark hair pulled back into a sleek low ponytail, warm medium-tan skin, soft pink lips, and a bright YELLOW fleece zip-up top worn under a cozy LEOPARD-PRINT fuzzy fur coat."
PRE="Keep this EXACT chibi pixel character identical — same face, same big square tortoiseshell-and-gold glasses, same pulled-back dark hair, same yellow top under the leopard-print fur coat, same FRONT-FACING forward pose, same proportions and pixel-art style, transparent background. Change ONLY: "
BLINKPRE="Keep this EXACT chibi pixel character identical — same outfit, same big square glasses, same hair, same front-facing pose, same everything. Change ONLY: both eyes gently closed in a soft blink behind the glasses. Transparent background, single centered character."

MOODS=(
"coding|a cozy focused look (she already wears glasses)"
"thinking|a little glowing yellow lightbulb floating above the head, a pondering look"
"meeting|sitting up attentively, holding a tiny coffee cup, looking engaged"
"communicating|wearing small headphones with a tiny speech bubble floating beside the head"
"browsing|holding a tiny smartphone in both hands, looking at it"
"creating|holding a tiny paintbrush and a small artist palette"
"vibing|wearing big headphones, eyes happily closed, a small music note floating"
"idle|eyes closed and head gently drooping, sleepy resting pose, small Zzz floating"
"pat|eyes happily closed in upward curved arcs, big rosy blush on the cheeks, a content smile"
"blink|both eyes gently closed in a soft blink behind the glasses, content"
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

[ -s "$RAW/photo.png" ] || magick "$PHOTO_SRC" "$RAW/photo.png"

if [ ! -s "$OUT/neutral.png" ]; then
  echo ">> base…"
  [ -s "$RAW/base.png" ] || edit "$RAW/photo.png" "$BASE" "$RAW/base.png" || { echo "BASE FAILED"; exit 1; }
  pixelate "$RAW/base.png" "$OUT/neutral.png"; echo ">> neutral done"
fi

for m in "${MOODS[@]}"; do
  name="${m%%|*}"; detail="${m#*|}"
  [ -s "$OUT/$name.png" ] && continue
  ( if edit "$RAW/base.png" "$PRE $detail" "$RAW/$name.png"; then
      pixelate "$RAW/$name.png" "$OUT/$name.png" "$OUT/neutral.png"; echo ">> $name ok"
    else echo ">> $name FAILED"; fi ) &
  while [ "$(jobs -r | wc -l)" -ge "$MAX" ]; do sleep 2; done
done
wait

for m in "${BLINKMOODS[@]}"; do
  out="$OUT/$m-blink.png"
  [ -s "$out" ] && continue
  [ -s "$RAW/$m.png" ] || { echo ">> no raw $m"; continue; }
  ( if edit "$RAW/$m.png" "$BLINKPRE" "$RAW/$m-blink.png"; then
      pixelate "$RAW/$m-blink.png" "$out" "$OUT/neutral.png"; echo ">> $m-blink ok"
    else echo ">> $m-blink FAILED"; fi ) &
  while [ "$(jobs -r | wc -l)" -ge "$MAX" ]; do sleep 2; done
done
wait

echo "DONE shreya: $(ls "$OUT" | wc -l | tr -d ' ') sprites"
