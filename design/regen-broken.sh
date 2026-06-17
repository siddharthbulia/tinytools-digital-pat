#!/usr/bin/env bash
# Regenerate the 10 QA-confirmed broken sprites (mostly background-not-removed + one blob).
# Hardened transparent-bg prompt + a transparency CHECK that retries if the API returns an
# opaque background again. Rebuilds dependent blinks from the fixed base. Idempotent per target.
set -uo pipefail

KEY=$(grep -o 'sk-[A-Za-z0-9_-]*' ~/.gstack/openai.json | head -1)
CHARS=/Users/siddharthbulia/Code/app-factory/apps/digital-pat/characters
RAW=~/.gstack/projects/digital-pat/people
M=/opt/homebrew/bin/magick

TRANSP=" The background MUST be 100% transparent (alpha) — absolutely NO background color, no dark box, no scene, no frame. One single centered character only, nothing else in the image."
PRE="Keep this EXACT chibi pixel character identical — same face, same hair/headwear, same FRONT-FACING forward pose, same proportions and pixel-art style. Change ONLY: "
BLINKPRE="Keep this EXACT chibi pixel character identical — same outfit, same hair/headwear, same front-facing pose, same everything. Change ONLY: both eyes gently closed in a soft blink."

# id|mood|detail   (pat has no blink; others get a dependent blink rebuilt)
TARGETS=(
"ankit-aggarwal|thinking|add small round glasses and a little glowing yellow lightbulb floating above the head"
"ankit-choudhary|thinking|add small round glasses and a little glowing yellow lightbulb floating above the head"
"shubham|browsing|holding a tiny smartphone in both hands, looking at it"
"siddhanth|pat|eyes happily closed in upward curved arcs, big rosy blush on the cheeks, a content smile"
"dushyant|communicating|wearing small headphones with a tiny speech bubble floating beside the head"
"ven|meeting|wearing a smart dark blazer, sitting up attentively"
)
BLINKMOODS="coding thinking meeting communicating browsing creating"

apicall () { # $1 input  $2 prompt  $3 outraw  -> 0 if result has real transparency
  local i a
  for i in 1 2 3 4; do
    curl -s https://api.openai.com/v1/images/edits \
      -H "Authorization: Bearer $KEY" -F model=gpt-image-1 -F image="@$1;type=image/png" \
      -F size=1024x1024 -F quality=medium -F background=transparent -F n=1 -F prompt="$2" \
      | python3 -c "import sys,json,base64; d=json.load(sys.stdin); open('$3','wb').write(base64.b64decode(d['data'][0]['b64_json']))" 2>/dev/null
    [ -s "$3" ] || { sleep 4; continue; }
    # transparency check: needs an alpha channel AND meaningful transparent area
    a=$("$M" "$3" -format "%[fx:mean.a]" info: 2>/dev/null)
    awk -v a="${a:-1}" 'BEGIN{exit !(a>0.08 && a<0.92)}' && return 0
    echo "   (retry $i: bg not transparent, mean.a=$a)"; sleep 3
  done
  return 1
}
pixelate () { "$M" "$1" -background none -resize 64x64 -channel A -threshold 45% +channel -remap "$3" -dither None -scale 512x512 "$2"; }

for t in "${TARGETS[@]}"; do
  id="${t%%|*}"; rest="${t#*|}"; mood="${rest%%|*}"; detail="${rest#*|}"
  pal="$CHARS/$id/neutral.png"; base="$RAW/$id/base.png"
  [ -s "$pal" ] && [ -s "$base" ] || { echo ">> [$id/$mood] MISSING base/palette"; continue; }
  echo ">> [$id/$mood] regenerating base mood…"
  if apicall "$base" "$PRE $detail.$TRANSP" "$RAW/$id/$mood.png"; then
    pixelate "$RAW/$id/$mood.png" "$CHARS/$id/$mood.png" "$pal"
    echo ">> [$id/$mood] base OK"
    if echo " $BLINKMOODS " | grep -q " $mood "; then
      echo ">> [$id/$mood-blink] regenerating blink from fixed base…"
      if apicall "$RAW/$id/$mood.png" "$BLINKPRE$TRANSP" "$RAW/$id/$mood-blink.png"; then
        pixelate "$RAW/$id/$mood-blink.png" "$CHARS/$id/$mood-blink.png" "$pal"
        echo ">> [$id/$mood-blink] OK"
      else echo ">> [$id/$mood-blink] FAILED"; fi
    fi
  else echo ">> [$id/$mood] FAILED"; fi
done
echo "REGEN DONE"
