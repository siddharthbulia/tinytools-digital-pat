#!/usr/bin/env bash
# Flag likely-bad sprites: near-empty, background-not-removed, or far off the character's
# own anchor (neutral for moods; the mood itself for its blink). Copies suspects to a
# review folder with the neutral beside them. Regenerates NOTHING.
set -uo pipefail

CHARS=/Users/siddharthbulia/Code/app-factory/apps/digital-pat/characters
REVIEW=/Users/siddharthbulia/Code/app-factory/apps/digital-pat/characters-review
rm -rf "$REVIEW"; mkdir -p "$REVIEW"
REPORT="$REVIEW/flagged.txt"; : > "$REPORT"

meanalpha () { magick "$1" -format "%[fx:mean.a]" info: 2>/dev/null; }
rmse () { magick compare -metric RMSE "$1" "$2" null: 2>&1 | sed -E 's/.*\(([0-9.]+)\).*/\1/'; }

for d in "$CHARS"/*/; do
  id=$(basename "$d"); neutral="${d}neutral.png"
  [ -s "$neutral" ] || continue
  for f in "$d"*.png; do
    name=$(basename "$f" .png)
    a=$(meanalpha "$f")
    ref="$neutral"
    case "$name" in
      *-blink) base="${name%-blink}"; [ -s "$d$base.png" ] && ref="$d$base.png" ;;
    esac
    r=$(rmse "$ref" "$f")
    reason=$(awk -v a="${a:-1}" -v r="${r:-0}" -v n="$name" 'BEGIN{
      reason="";
      if (a < 0.10) reason="near-empty";
      else if (a > 0.96) reason="no-transparency";
      else if (n ~ /-blink$/ && r+0 > 0.16) reason="blink-deviates";
      else if (n !~ /-blink$/ && n != "neutral" && r+0 > 0.33) reason="off-model?";
      print reason;
    }')
    if [ -n "$reason" ]; then
      mkdir -p "$REVIEW/$id"
      cp "$f" "$REVIEW/$id/"
      cp "$neutral" "$REVIEW/$id/_neutral.png" 2>/dev/null
      printf '%-30s alpha=%-6s rmse=%-7s -> %s\n' "$id/$name" "$a" "$r" "$reason" >> "$REPORT"
    fi
  done
done
echo "=== flagged ($(wc -l < "$REPORT" | tr -d ' ')) ==="
sort "$REPORT"
# montage all flagged for visual review
mapfile -t FILES < <(awk '{print $1}' "$REPORT" | sed "s#^#$CHARS/#; s#\$#.png#")
[ "${#FILES[@]}" -gt 0 ] && magick montage "${FILES[@]}" -tile 6x -geometry 150x150+4+4 \
  -background "#241d35" -fill "#ffd6e8" -pointsize 13 -label '%d' "$REVIEW/_flagged-montage.png" 2>/dev/null
echo "review folder: $REVIEW"
