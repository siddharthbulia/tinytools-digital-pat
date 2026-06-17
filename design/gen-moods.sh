#!/usr/bin/env bash
# Generate the full mood set for the locked pixel kitten, keeping the same character
# (via the image-edit endpoint) and the same palette (via -remap to the hero sprite).
set -uo pipefail

KEY=$(grep -o 'sk-[A-Za-z0-9_-]*' ~/.gstack/openai.json | head -1)
REF=~/.gstack/projects/digital-pat/designs/kitten-styles-20260613/pixA.png      # raw hero reference
HERO64=/Users/siddharthbulia/Code/app-factory/apps/digital-pat/design/concepts/pixel/pixA-64.png  # palette source
RAW=~/.gstack/projects/digital-pat/designs/kitten-styles-20260613/moods
OUT=/Users/siddharthbulia/Code/app-factory/apps/digital-pat/design/concepts/pixel/moods
mkdir -p "$RAW" "$OUT"

PRE="Keep this EXACT adorable pixel-art kitten: same cream and peach fur, same big sparkly eyes with white catchlight, same proportions, same retro Tamagotchi pixel-art style, sitting, transparent background. Change ONLY the following:"

declare -a MOODS=(
  "coding|wearing tiny round eyeglasses and a small cozy hoodie, focused content expression"
  "thinking|wearing tiny round glasses with a small glowing yellow lightbulb floating above its head, curious look"
  "meeting|wearing a tiny smart dark blazer over its fur, sitting up straight and attentive"
  "communicating|wearing small headphones with a tiny speech bubble floating beside its head"
  "browsing|holding a tiny smartphone in its little paws, looking at it curiously"
  "creating|wearing a little red artist beret and holding a tiny paintbrush"
  "vibing|wearing big headphones, eyes happily closed, a small music note floating nearby, gently swaying"
  "idle|curled up sleepy wearing a tiny pink nightcap, small Zzz floating, eyes closed"
  "pat|eyes happily closed in upward curved arcs, big rosy blush, several small floating hearts, extremely happy purring"
)

edit_one () { # $1 name  $2 detail
  local name="$1" detail="$2" tmp="$RAW/$1.png"
  echo ">> $name"
  curl -s https://api.openai.com/v1/images/edits \
    -H "Authorization: Bearer $KEY" \
    -F model=gpt-image-1 \
    -F image="@$REF" \
    -F size=1024x1024 -F quality=medium -F background=transparent -F n=1 \
    -F prompt="$PRE $detail" \
    | python3 -c "import sys,json,base64; d=json.load(sys.stdin); open('$tmp','wb').write(base64.b64decode(d['data'][0]['b64_json'])); print('   raw ok')" \
    || { echo "   FAILED $name"; return 1; }
  # pixelate + remap to hero palette for a cohesive set
  magick "$tmp" -background none -resize 64x64 -channel A -threshold 45% +channel \
    -remap "$HERO64" -dither None -scale 512x512 "$OUT/$name.png"
  echo "   pixel ok -> $OUT/$name.png"
}

for m in "${MOODS[@]}"; do
  edit_one "${m%%|*}" "${m#*|}"
done
echo "ALL DONE"
ls -1 "$OUT"
