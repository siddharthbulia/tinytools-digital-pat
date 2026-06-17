#!/usr/bin/env bash
# Generate the "GD" character: a cute chibi pixel mascot from a real photo, all mood variants.
set -uo pipefail

KEY=$(grep -o 'sk-[A-Za-z0-9_-]*' ~/.gstack/openai.json | head -1)
PHOTO="/Users/siddharthbulia/.claude/image-cache/510989db-9381-4db2-9f1c-3ce84b976b88/5.png"
RAW=~/.gstack/projects/digital-pat/designs/gd
OUT=/Users/siddharthbulia/Code/app-factory/apps/digital-pat/characters/gd
mkdir -p "$RAW" "$OUT"

pixelate () {  # $1 raw  $2 out  $3 paletteSource(optional, else self-quantize)
  if [ -n "${3:-}" ]; then
    magick "$1" -background none -resize 64x64 -channel A -threshold 45% +channel -remap "$3" -dither None -scale 512x512 "$2"
  else
    magick "$1" -background none -resize 64x64 -channel A -threshold 45% +channel -colors 24 -dither None -scale 512x512 "$2"
  fi
}

# ---- 1. base (neutral) from the photo ----
echo ">> base"
BASE="Turn this person into an ADORABLE chibi pixel-art mascot in a cute retro Tamagotchi style: huge round head about 60% of the body, big sparkly low-set eyes with white catchlights, tiny rounded body, sitting and facing forward, thick clean outline, soft warm palette, transparent background, single centered character. KEEP their identity clearly: a white Sikh turban (dastar), short black beard, a cream hoodie under a dark denim jacket, warm medium skin tone."
curl -s https://api.openai.com/v1/images/edits \
  -H "Authorization: Bearer $KEY" -F model=gpt-image-1 -F image="@$PHOTO" \
  -F size=1024x1024 -F quality=medium -F background=transparent -F n=1 \
  -F prompt="$BASE" \
  | python3 -c "import sys,json,base64; d=json.load(sys.stdin); open('$RAW/base.png','wb').write(base64.b64decode(d['data'][0]['b64_json'])); print('   base raw ok')" \
  || { echo "   BASE FAILED"; exit 1; }
pixelate "$RAW/base.png" "$OUT/neutral.png"   # self-quantize -> defines GD palette
PAL="$OUT/neutral.png"

# ---- 2. mood variants from the base ----
PRE="Keep this EXACT chibi pixel character identical — same face, same white turban, same black beard, same proportions and pixel-art style, transparent background. Change ONLY the following:"
declare -a M=(
  "coding|add small round eyeglasses, a cozy focused look"
  "thinking|add small round glasses and a little glowing yellow lightbulb floating above the head"
  "meeting|wearing a smart dark blazer over the hoodie, sitting up attentively"
  "communicating|wearing small headphones with a tiny speech bubble floating beside the head"
  "browsing|holding a tiny smartphone in both hands, looking at it"
  "creating|holding a tiny paintbrush and a small artist palette"
  "vibing|wearing big headphones, eyes happily closed, a small music note floating"
  "idle|eyes closed and head gently drooping, sleepy resting pose, small Zzz floating"
  "pat|eyes happily closed in upward curved arcs, big rosy blush on the cheeks, a content smile"
  "blink|both eyes gently closed in a soft blink, content"
)
for m in "${M[@]}"; do
  name="${m%%|*}"; detail="${m#*|}"
  echo ">> $name"
  curl -s https://api.openai.com/v1/images/edits \
    -H "Authorization: Bearer $KEY" -F model=gpt-image-1 -F image="@$RAW/base.png" \
    -F size=1024x1024 -F quality=medium -F background=transparent -F n=1 \
    -F prompt="$PRE $detail" \
    | python3 -c "import sys,json,base64; d=json.load(sys.stdin); open('$RAW/$name.png','wb').write(base64.b64decode(d['data'][0]['b64_json'])); print('   raw ok')" \
    && pixelate "$RAW/$name.png" "$OUT/$name.png" "$PAL" \
    || echo "   FAILED $name"
done
echo "ALL DONE"; ls -1 "$OUT" | tr '\n' ' '; echo
