#!/usr/bin/env python3
import json, os, re, sys

DST = "/Users/siddharthbulia/Code/app-factory/apps/digital-pat/design/wireframes"
PARTS = os.path.join(DST, "parts")
split = json.load(open(os.path.join(DST, "split.json")))

ORDER = ["pet-and-motion", "tend-me", "pats-diary", "helper-basics",
         "onboarding", "menu-settings", "architecture"]
NAV = {
    "pet-and-motion": "01 · Pet & Motion",
    "tend-me": "02 · Tend-me",
    "pats-diary": "03 · Pat’s Diary",
    "helper-basics": "04 · Helper basics",
    "onboarding": "05 · First run",
    "menu-settings": "06 · Menu & settings",
    "architecture": "07 · Architecture",
}

# ---- CSS: fix stray-hex bug + append .px / .subkicker / broaden cap-em ----
css = open(os.path.join(PARTS, "_style-orig.css"), encoding="utf-8").read()
css = css.replace("#dcecc f", "#dcecd0")
css += """

/* ---- post-review additions ---- */
.px{ image-rendering:pixelated; image-rendering:crisp-edges; width:100%; height:100%; object-fit:contain; display:block; }
.frame .px{ max-height:100%; }
.subkicker{ display:inline-flex; align-items:center; gap:7px; font-size:11.5px; font-weight:700;
  letter-spacing:.08em; text-transform:uppercase; color:var(--ink-3); margin:22px 0 8px; }
.frame figcaption em, .frame .cap em{ color:var(--pink-ink); font-style:normal; font-weight:700; }
"""

# ---- sections: prefer fixed-<id>.html, fall back to original ----
sections = []
report = []
for sid in ORDER:
    fixed = os.path.join(PARTS, f"fixed-{sid}.html")
    orig = os.path.join(PARTS, f"{sid}.html")
    use, why = None, ""
    if os.path.exists(fixed):
        blk = open(fixed, encoding="utf-8").read().strip()
        # strip any code fences an agent might have added
        blk = re.sub(r"^```[a-z]*\n", "", blk); blk = re.sub(r"\n```$", "", blk)
        if f'id="{sid}"' in blk and blk.count("<section") >= 1 and len(blk) > 800:
            use, why = blk, "fixed"
        else:
            use, why = split["sections"][sid], "FALLBACK (fixed invalid)"
    else:
        use, why = split["sections"][sid], "FALLBACK (no fixed file)"
    sections.append(use)
    report.append(f"  {sid}: {why} ({len(use)} bytes)")

nav_links = "\n      ".join(f'<a href="#{sid}">{NAV[sid]}</a>' for sid in ORDER)
body = "\n\n".join(sections)

html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Digital Pat — Wireframes</title>
<style>
{css}
</style>
</head>
<body>
  <div class="wrap">
    <header class="hero">
      <span class="eyebrow">Wireframes · v1 direction</span>
      <div class="hero-pet">🐱</div>
      <h1>Digital Pat — a cute helper kitten</h1>
      <p class="sub">A sweet pixel-art companion that lives on your desktop, walks when you drag it, lets you tend to it, and fondly recaps your day. It keeps you company and helps with little basics. It is <strong>not</strong> a tracker.</p>
    </header>
    <nav class="toc">
      <span class="toc-label">🐾 Pat</span>
      {nav_links}
    </nav>
{body}
    <footer>Digital Pat · wireframes · a cute helper, not a tracker · <span class="heart">♥</span> everything stays on your mac</footer>
  </div>
</body>
</html>"""

open(os.path.join(DST, "wireframes.html"), "w", encoding="utf-8").write(html)
print("reassembled wireframes.html:", len(html), "bytes")
print("\n".join(report))
