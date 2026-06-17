#!/usr/bin/env bash
# Generate cute pixel characters for the whole Slack roster (custom-photo folks only).
# Front-facing pose enforced regardless of how the source photo is angled.
# 3 people in parallel, resumable (skips sprites that already exist).
set -uo pipefail

KEY=$(grep -o 'sk-[A-Za-z0-9_-]*' ~/.gstack/openai.json | head -1)
OUTROOT=/Users/siddharthbulia/Code/app-factory/apps/digital-pat/characters
RAWROOT=~/.gstack/projects/digital-pat/people
MAX=3

# slug|imageURL  (custom-photo members; tarun/arjun/vaishali/nash skipped = default avatars; gd already done)
ROSTER=(
"ven|https://avatars.slack-edge.com/2024-01-18/6508269268641_1b0831e64109264b725b_original.png"
"chirag|https://avatars.slack-edge.com/2024-01-06/6418379913815_98d6d8e316c9fb4ae84d_original.png"
"dushyant|https://avatars.slack-edge.com/2024-07-23/7463141615875_18c577e4e21b4fe0ce07_original.jpg"
"akshay|https://avatars.slack-edge.com/2024-08-15/7570311681414_2e097133d7ebc07ef943_original.jpg"
"rohan|https://avatars.slack-edge.com/2025-01-07/8242839505847_57b142ad0184d7f607c8_original.jpg"
"joe|https://avatars.slack-edge.com/2026-02-14/10512532276738_1a7d5f063732cfc542e1_original.png"
"siddharth|https://avatars.slack-edge.com/2024-01-06/6429972715397_2813c3bde8a50df5b960_original.jpg"
"shubham|https://avatars.slack-edge.com/2025-04-13/8732904673607_23aa33c0bfa5bdd8f58b_original.jpg"
"siddhanth|https://avatars.slack-edge.com/2025-03-27/8670423486340_162f4a72c84216c80e90_original.jpg"
"hemant|https://avatars.slack-edge.com/2025-04-04/8710412811234_80ec98c9b4201ab56714_original.png"
"pushkar|https://avatars.slack-edge.com/2025-04-21/8772835922614_7aaff41ce5800d1edf88_original.jpg"
"ankit|https://avatars.slack-edge.com/2025-05-01/8835545455762_e14ab6b2f76245bf6524_original.png"
"ajinkya|https://avatars.slack-edge.com/2025-05-13/8890311821474_c8b929fba1206e07cc0a_original.png"
"chahek|https://avatars.slack-edge.com/2025-06-30/9126490764450_5549b50e458e2bb1aead_original.png"
"ankit-aggarwal|https://avatars.slack-edge.com/2025-07-29/9272587025284_cdad5eef184d5717be92_original.jpg"
"niral|https://avatars.slack-edge.com/2026-02-24/10567520325478_900b5054a4e36a6817ce_original.png"
"jasleen|https://avatars.slack-edge.com/2026-02-05/10444354331027_3934f81f6692acb92868_original.jpg"
"pooja|https://avatars.slack-edge.com/2026-04-20/10952855538582_dc5cdbdf14614e147503_original.png"
"ankit-choudhary|https://avatars.slack-edge.com/2026-05-12/11105843705554_39b339fd177661104b50_original.png"
"yashika|https://avatars.slack-edge.com/2026-06-01/11250925891637_ffc28b3f1bdc04987ebb_original.jpg"
)

FRONT="The mascot MUST FACE THE VIEWER HEAD-ON — a front-facing, forward-looking, upright, centered pose looking straight at the camera — NO MATTER how the source photo is angled, turned, or cropped."
BASE="Turn this person into an ADORABLE chibi pixel-art mascot, cute retro Tamagotchi style. $FRONT Huge round head about 60% of the body, big sparkly low-set eyes with white catchlights, tiny rounded body, sitting, thick clean outline, soft warm palette, transparent background, single centered character. Keep their most recognizable features (hairstyle, facial hair, glasses, skin tone, signature clothing/headwear)."
PRE="Keep this EXACT chibi pixel character identical — same face, same hair/headwear, same FRONT-FACING forward pose, same proportions and pixel-art style, transparent background. Change ONLY: "

MOODS=(
"coding|add small round eyeglasses, a cozy focused look"
"thinking|add small round glasses and a little glowing yellow lightbulb floating above the head"
"meeting|wearing a smart dark blazer, sitting up attentively"
"communicating|wearing small headphones with a tiny speech bubble floating beside the head"
"browsing|holding a tiny smartphone in both hands, looking at it"
"creating|holding a tiny paintbrush and a small artist palette"
"vibing|wearing big headphones, eyes happily closed, a small music note floating"
"idle|eyes closed and head gently drooping, sleepy resting pose, small Zzz floating"
"pat|eyes happily closed in upward curved arcs, big rosy blush on the cheeks, a content smile"
"blink|both eyes gently closed in a soft blink, content"
)

edit () {  # $1 inputImage  $2 prompt  $3 outRaw  -> returns 0 on success
  local i
  for i in 1 2 3; do
    curl -s https://api.openai.com/v1/images/edits \
      -H "Authorization: Bearer $KEY" -F model=gpt-image-1 -F image="@$1;type=image/png" \
      -F size=1024x1024 -F quality=medium -F background=transparent -F n=1 \
      -F prompt="$2" \
      | python3 -c "import sys,json,base64; d=json.load(sys.stdin); open('$3','wb').write(base64.b64decode(d['data'][0]['b64_json']))" 2>/dev/null \
      && [ -s "$3" ] && return 0
    sleep 5
  done
  return 1
}
pixelate () {  # $1 raw  $2 out  $3 palette(optional)
  if [ -n "${3:-}" ]; then
    magick "$1" -background none -resize 64x64 -channel A -threshold 45% +channel -remap "$3" -dither None -scale 512x512 "$2"
  else
    magick "$1" -background none -resize 64x64 -channel A -threshold 45% +channel -colors 24 -dither None -scale 512x512 "$2"
  fi
}

person () {
  local slug="${1%%|*}" url="${1#*|}"
  local raw="$RAWROOT/$slug" out="$OUTROOT/$slug"
  mkdir -p "$raw" "$out"
  echo ">> [$slug] start"
  [ -f "$raw/photo" ] || curl -s -L "$url" -o "$raw/photo"
  [ -s "$raw/photo.png" ] || magick "$raw/photo" "$raw/photo.png" 2>/dev/null   # normalize to real PNG
  # base / neutral
  if [ ! -s "$out/neutral.png" ]; then
    [ -s "$raw/base.png" ] || edit "$raw/photo.png" "$BASE" "$raw/base.png" || { echo ">> [$slug] BASE FAILED"; return 1; }
    pixelate "$raw/base.png" "$out/neutral.png"
  fi
  # moods
  for m in "${MOODS[@]}"; do
    local name="${m%%|*}" detail="${m#*|}"
    [ -s "$out/$name.png" ] && continue
    if edit "$raw/base.png" "$PRE $detail" "$raw/$name.png"; then
      pixelate "$raw/$name.png" "$out/$name.png" "$out/neutral.png"
    else
      echo ">> [$slug] skip $name (failed)"
    fi
  done
  echo ">> [$slug] done ($(ls "$out" | wc -l | tr -d ' ') sprites)"
}

for entry in "${ROSTER[@]}"; do
  person "$entry" &
  while [ "$(jobs -r | wc -l)" -ge "$MAX" ]; do sleep 2; done
done
wait
echo "ALL PEOPLE DONE"
ls -d "$OUTROOT"/*/ | xargs -n1 basename | tr '\n' ' '; echo
