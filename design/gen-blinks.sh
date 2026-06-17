#!/usr/bin/env bash
# Generate a per-mood BLINK frame (same outfit, eyes closed) for every character,
# for the open-eye moods. Resumable. Auto-discovers all characters/* (cat, gd, people).
set -uo pipefail

KEY=$(grep -o 'sk-[A-Za-z0-9_-]*' ~/.gstack/openai.json | head -1)
CHARS=/Users/siddharthbulia/Code/app-factory/apps/digital-pat/characters
RAWPEOPLE=~/.gstack/projects/digital-pat/people
GDRAW=~/.gstack/projects/digital-pat/designs/gd
CATRAW=~/.gstack/projects/digital-pat/designs/kitten-styles-20260613/moods
MAX=3
BLINKMOODS=(coding thinking meeting communicating browsing creating)
PRE="Keep this EXACT chibi pixel character identical — same outfit, same hair/headwear, same front-facing pose, same everything. Change ONLY: both eyes gently closed in a soft blink. Transparent background, single centered character."

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
pixelate () { magick "$1" -background none -resize 64x64 -channel A -threshold 45% +channel -remap "$3" -dither None -scale 512x512 "$2"; }

# resolve a raw (1024) source for a character's mood, else fall back to the bundled 512 sprite
rawsrc () {  # $1 id  $2 mood
  local id="$1" m="$2"
  for c in "$RAWPEOPLE/$id/$m.png" "$( [ "$id" = gd ] && echo "$GDRAW/$m.png" )" \
           "$( [ "$id" = cat ] && echo "$CATRAW/$m.png" )" "$CHARS/$id/$m.png"; do
    [ -n "$c" ] && [ -s "$c" ] && { echo "$c"; return; }
  done
}

charblinks () {
  local id="$1" pal="$CHARS/$id/neutral.png" raw="$RAWPEOPLE/$id"
  [ -s "$pal" ] || return 0
  mkdir -p "$raw"
  for m in "${BLINKMOODS[@]}"; do
    local out="$CHARS/$id/$m-blink.png"
    [ -s "$out" ] && continue
    [ -s "$CHARS/$id/$m.png" ] || continue   # no such mood sprite for this character
    local src; src=$(rawsrc "$id" "$m"); [ -z "$src" ] && continue
    if edit "$src" "$PRE" "$raw/$m-blink.png"; then
      pixelate "$raw/$m-blink.png" "$out" "$pal"
      echo ">> [$id] $m-blink ok"
    else
      echo ">> [$id] $m-blink FAILED"
    fi
  done
}

for d in "$CHARS"/*/; do
  id=$(basename "$d")
  charblinks "$id" &
  while [ "$(jobs -r | wc -l)" -ge "$MAX" ]; do sleep 2; done
done
wait
echo "ALL BLINKS DONE"
for d in "$CHARS"/*/; do echo -n "$(basename "$d"):$(ls "$d"|wc -l|tr -d ' ') "; done; echo
