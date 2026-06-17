# DESIGN.md — Digital Pat (the kitten)

The single source of truth for how Pat looks, moves, and feels. Everything we generate,
commission, or hand-build must obey this. If a render violates the cuteness formula or the
motion principles, it's wrong even if it's "nice." Cute is a recipe, not a vibe.

---

## 1. Who Pat is (personality drives the art)

Pat is a **baby kitten** — shy but deeply affectionate, calm, supportive, never judgmental.
It is not hyper, not a clown, not sassy. It quietly hangs out while you work and is genuinely
happy you're there. When you pat it, it **slow-blinks** (the real-cat "I love you") and purrs.

Three words: **sweet, soft, present.** Every pose and expression should read as one of those.

Anti-character: nothing edgy, nothing "cool," nothing with attitude. No big anime sparkle-rage,
no smug grin. Pat's superpower is being gentle.

---

## 2. The cuteness formula (kindchenschema) — non-negotiable proportions

Cuteness is baby-schema. Hit these or it won't read as cute:

- **Head ≈ 55–60% of total height.** Big head, small body. This is the #1 lever.
- **Eyes large and set LOW** — pupils centered around or just below the face's vertical midline,
  not up high. Big iris, big catchlights. Eye width ≈ 1/4 of face width each, with real spacing.
- **Catchlights:** one big highlight (upper) + one small (lower-opposite). Glossy, alive.
- **Tiny nose + tiny mouth**, placed close together, low on the face. Small = baby.
- **Fat cheeks, round chin, no jaw.** The face silhouette is a soft circle/egg, never angular.
- **Stubby limbs, no neck.** Paws are little jellybeans. Body is a soft blob.
- **Slight head tilt + subtle asymmetry.** Perfect symmetry reads robotic. Tilt ~5–8°.
- **Ears:** rounded triangles, soft tips (not sharp daggers), with pink inner ears.

Quick self-test on any candidate art: *cover the body — is the head alone adorable?* If not, reject.

---

## 3. Aesthetic directions (we're shotgunning all 4, then picking)

All four obey §2. They differ in rendering, not in proportions.

| Dir | Name | Rendering | Reference touchstones |
|----|------|-----------|------------------------|
| 1 | **3D Clay Cutie** | Soft claymorphism / 3D render, matte clay material, gentle ambient occlusion + soft shadow, tiny rim light | Pinterest "claymorphism mascot", soft C4D characters, the "3D blob pet" look |
| 2 | **Sanrio Sticker Kawaii** | Flat 2D, clean even outline, pastel fills, die-cut white sticker border | Pusheen, Sanrio, Hello Kitty sticker sheets |
| 3 | **Pixel Tamagotchi** | Crisp pixel art, ~32–48px native grid scaled up, limited palette, dithered shading | Tamagotchi, Stardew pets, retro Y2K virtual pets |
| 4 | **Risograph Storybook** | Textured 2-3 ink risograph look, grain, slight misregistration, muted inks | Riso print zines, indie storybook illustration |

Each must work as a **transparent-background character** (it floats on the desktop).

---

## 4. Palette

**Shared base kitten:** warm cream fur `#FBF3E8`, soft shade `#EBDFCD`, warm outline `#6B5B53`,
pink inner-ear / nose `#FF9FB6`, blush `#FFB3C8`, eye near-black `#2B2330`.

**Gen-Z accent palettes** (pick per direction; these set the "vibe" more than anything):
- **Strawberry milk:** `#FFE3EC` `#FFB3C8` `#FF8FB1` `#7A6F85`
- **Matcha latte:** `#EAF3E0` `#Bcd9a6` `#8FBF7A` `#5C6B4E`
- **Butter + sage:** `#FFF1C9` `#F4E3A1` `#BFD8B8` `#6B7A5E`
- **Lilac dream:** `#F3ECFF` `#D9C7FF` `#B49BFF` `#5E5470`
- **Y2K cyber (pixel only):** `#9BF6FF` `#FF6AD5` `#C8FF6A` `#1C1726`

Rule: **2 fills + 1 outline/ink + 1 accent**, max. More colors = less cute. Grainy gradients > flat
for dirs 1 & 4. Always keep the fur readable against both light and dark wallpapers (that's why
dirs 2 & 5-style get a thin light "sticker" rim).

---

## 5. Line, form, texture

- **Outline:** warm dark brown `#6B5B53`, never pure black (except Pixel/Sticker where bold is the point).
  Vary weight slightly — thicker on the outer silhouette, thinner on interior lines. Uniform line = flat.
- **Forms:** everything rounded. No corner sharper than a fingertip. Tangents avoided.
- **Texture:** dirs 1 & 4 get subtle grain/noise (~3–6% opacity). It instantly kills the "default vector" look.
- **Shadow:** one soft contact shadow under the body (grounds it). Dir 1 adds gentle AO in the creases.

---

## 6. Motion (half the cuteness lives here)

Cuteness is in **slow, soft easing.** Nothing snappy, nothing linear.

**Idle loop (always running):**
- breathing: body scales ~2–3% on a 2.5–3s ease-in-out, anchored at the feet.
- blink: every 3–6s, quick (~120ms) — but occasionally a **slow blink** (see purr).
- micro: ear twitch or tail flick every ~6–10s. Never both at once. Keep it lazy.

**Mood transitions:** a tiny hop or a "poof" + the new outfit settles in. ~300ms spring, gentle overshoot.

### The sweet purr (the money moment) — spec
When patted:
1. Eyes **ease slowly closed** into happy `‿‿` arcs over ~400ms (the slow-blink — the whole point).
2. Body does a soft **squash (~6%) + lean toward the cursor** ~3px.
3. A gentle **vibration** — 1–2px vertical jitter at ~12–16Hz for ~1s (the purr you can *see*).
4. **Hearts** of varied sizes drift up, slow ease-out, slight horizontal wander, fade over ~1s.
5. Soft `prrr~` in a rounded bubble (lowercase, rounded font).
6. Optional: a short, soft **purr sound** loop (huge sweetness payoff; ship if asset budget allows).
Timing law: everything here is SLOW and eased. If it feels snappy, it's wrong.

---

## 7. Mood + outfit system (consistent with PRD §6.3)

Same base kitten, swap one outfit/prop + eye state + caption. 8 moods + default + pat.

| Mood | App trigger | Prop / outfit | Eye state |
|------|-------------|---------------|-----------|
| Coding | VS Code, Xcode, Terminal, Cursor | tiny glasses + hoodie | focused |
| Thinking | Claude, ChatGPT, Perplexity, PDFs | round glasses + lightbulb | up/curious |
| Meeting | Zoom, Meet, Teams, FaceTime | little blazer | attentive |
| Communicating | Slack, Mail, Messages, Discord | headphones + speech bubbles | normal |
| Browsing | Chrome, Safari, Arc | holding tiny phone | drifting |
| Creating | Figma, Photoshop, Canva | beret + brush | bright |
| Vibing | Spotify, Music, YouTube | headphones, swaying | closed/blissful |
| Idle | 2 min no input | nightcap, curled loaf | closed (sleep) |
| Pat | (click) | blush + sparkle | slow-blink ‿‿ |

Keep props **small and obvious in silhouette** — they must read at 120px on a busy desktop.

---

## 8. Production pipeline (the real quality unlock)

Hand-drawn SwiftUI shapes (v1) have a low ceiling. To get "extremely cute," move to assets:

- **Recommended: Rive.** A designer builds Pat as one file with a **state machine** (idle / each mood /
  pat trigger / slow-blink). The app feeds inputs ("mood = coding", "patted = true"); Rive handles the
  animation + blending. Purpose-built for reactive characters, tiny `.riv`, buttery vector. Best fit.
- **Alt: Lottie** (After Effects → JSON) — gorgeous vector loops, but state logic lives in app code.
- **Alt: PNG sprite sheets** — simplest, works everywhere, larger, manual frame work.

**Asset spec regardless of tech:** transparent background, square canvas, art safe-area ~80% (room for
hearts/Zzz), delivered at @1x/@2x/@3x or vector. One "rig" (the base kitten) + swappable prop layers so
we don't redraw the whole cat per mood.

---

## 9. Image-generation prompts (ready to fire once a key is added)

Base prompt (prepend to every style), tuned to §2:
> "Adorable chibi baby kitten mascot, oversized round head (~60% of body), huge low-set glossy sparkly
> eyes with double catchlights, tiny nose and mouth set low, fat cheeks, rosy blush, soft rounded squishy
> body, stubby jellybean paws, gentle head tilt, sitting neutral pose, warm cream fur, sweet and shy
> expression, centered single character, transparent or clean soft pastel background, character reference sheet."

Per-style suffix:
1. **3D Clay:** "claymorphism soft 3D render, matte clay material, soft studio lighting, gentle ambient occlusion, subtle rim light, soft contact shadow, pastel strawberry-milk palette."
2. **Sanrio Sticker:** "flat 2D kawaii, clean even outline, pastel fills, thick white die-cut sticker border, Sanrio / Pusheen style, minimal shading, matcha-latte palette."
3. **Pixel Tamagotchi:** "crisp pixel art, ~40px native resolution scaled up, limited Y2K palette, light dithering, retro virtual-pet sprite, black outline."
4. **Risograph:** "risograph print illustration, 2-3 muted ink colors, visible grain and paper texture, slight misregistration, storybook indie look, butter-and-sage palette."

Generation rules: 1 character per image, generous padding, NO text/watermarks/UI, NO background clutter.
Generate the **neutral pose** first to lock the look; only after a style wins do we render the mood set.

---

## 10. Do / Don't

**Do:** big head, low glossy eyes, slow eased motion, soft contact shadow, one accent color, slight tilt,
the slow-blink on pat, grain on dirs 1 & 4.

**Don't:** programmer-art geometric primitives, pure-black uniform outlines (except pixel/sticker), high
eyes / small eyes, sharp angles, busy multi-color palettes, snappy/linear motion, generic AI-slop "3D
mascot" with dead eyes, any expression with attitude. When unsure, make it softer and slower.
