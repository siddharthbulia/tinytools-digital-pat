#!/usr/bin/env python3
"""Render the CPTO plan JSON into a polished, self-contained HTML doc."""
import json, sys, html, datetime

SRC = sys.argv[1] if len(sys.argv) > 1 else "/tmp/cpto-plan.json"
OUT = sys.argv[2] if len(sys.argv) > 2 else \
    "/Users/siddharthbulia/Code/app-factory/apps/digital-pat/design/BUILD-PLAN.html"

data = json.load(open(SRC))
plan = data.get("plan", data)
reviews = data.get("reviews", [])

def esc(s): return html.escape(str(s))
def lis(items, cls=""):
    return "".join(f'<li class="{cls}">{esc(x)}</li>' for x in (items or []))

# Week 1 starts the Monday on/after today.
today = datetime.date(2026, 6, 13)
w1 = today + datetime.timedelta(days=(7 - today.weekday()) % 7 or 2)  # next Monday
def week_dates(n):
    s = w1 + datetime.timedelta(days=7 * (n - 1))
    e = s + datetime.timedelta(days=6)
    return f"{s.strftime('%b %-d')} – {e.strftime('%b %-d')}"

weeks = sorted(plan.get("weeks", []), key=lambda w: w.get("week", 0))

# ---- week cards ----
week_cards = []
for w in weeks:
    n = w.get("week", "?")
    risks = "".join(
        f'<div class="risk"><span class="rk">{esc(r.get("risk",""))}</span>'
        f'<span class="mit">→ {esc(r.get("mitigation",""))}</span></div>'
        for r in (w.get("risks") or [])
    )
    deps = ""
    if w.get("dependencies"):
        deps = '<div class="deps"><span class="deps-l">depends on</span> ' + \
               " · ".join(esc(d) for d in w["dependencies"]) + "</div>"
    week_cards.append(f"""
    <section id="w{n}" class="week">
      <div class="week-head">
        <div class="wnum">W{n}</div>
        <div>
          <div class="wdates">{week_dates(n)}</div>
          <h3 class="wtheme">{esc(w.get('theme',''))}</h3>
        </div>
      </div>
      <div class="milestone">🎯 <strong>Milestone:</strong> {esc(w.get('milestone',''))}</div>
      <div class="lanes">
        <div class="lane design"><div class="lane-h">🎨 Design</div><ul>{lis(w.get('design'))}</ul></div>
        <div class="lane eng"><div class="lane-h">⚙️ Engineering</div><ul>{lis(w.get('engineering'))}</ul></div>
        <div class="lane prod"><div class="lane-h">📦 Product</div><ul>{lis(w.get('product'))}</ul></div>
      </div>
      {deps}
      {'<div class="risks-row"><span class="risks-l">⚠ risks</span>'+risks+'</div>' if risks else ''}
      <div class="dod"><span class="dod-l">✓ definition of done</span><ul>{lis(w.get('definitionOfDone'))}</ul></div>
    </section>""")

# ---- releases timeline ----
rel_rows = "".join(
    f'<tr><td class="rtag">{esc(r.get("tag",""))}</td><td class="rwk">W{esc(r.get("week",""))}</td>'
    f'<td>{esc(r.get("scope",""))}</td></tr>'
    for r in sorted(plan.get("releases", []), key=lambda r: r.get("week", 0))
)

# ---- decision gates ----
gates = "".join(
    f'<div class="gate"><div class="gate-w">W{esc(g.get("week",""))} gate</div>'
    f'<div class="gate-q">{esc(g.get("question",""))}</div>'
    + (f'<div class="gate-yn"><span class="yes">if yes</span> {esc(g.get("ifYes",""))}</div>' if g.get("ifYes") else "")
    + (f'<div class="gate-yn"><span class="no">if no</span> {esc(g.get("ifNo",""))}</div>' if g.get("ifNo") else "")
    + "</div>"
    for g in plan.get("decisionGates", [])
)

# ---- risk register ----
sev_order = {"critical": 0, "high": 1, "medium": 2, "low": 3}
rr = sorted(plan.get("riskRegister", []), key=lambda r: sev_order.get(str(r.get("severity","")).lower(), 5))
risk_rows = "".join(
    f'<tr><td><span class="sev sev-{esc(str(r.get("severity","med")).lower())}">{esc(r.get("severity","—"))}</span></td>'
    f'<td>{esc(r.get("risk",""))}</td><td>{esc(r.get("mitigation",""))}</td>'
    f'<td class="kc">{esc(r.get("killCriterion","—"))}</td></tr>'
    for r in rr
)

# ---- toc ----
toc = "".join(f'<a href="#w{w.get("week")}">W{w.get("week")}</a>' for w in weeks)

review_chips = "".join(
    f'<span class="pill">{esc(r.get("lens","").split(":")[0].title())}: {esc(r.get("score","–"))}/10</span>'
    for r in reviews
)

HTML = f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{esc(plan.get('title','Digital Pat — Build Plan'))}</title>
<style>
:root{{--cream:#FBF3E8;--card:#FFFDF8;--ink:#4A3F47;--ink2:#7A6F78;--ink3:#A89DA3;
--line:#E9DCCB;--pink:#FF8FB1;--pink-ink:#C85F82;--pink-wash:#FFE7F0;
--sage:#BFD8B8;--sage-wash:#EAF3E0;--butter:#F4E3A1;--butter-wash:#FFF6D6;
--lilac:#D9C7FF;--lilac-wash:#F3ECFF;--sky-wash:#E6F4FA;
--good:#5FB07C;--warn:#E0A24A;--bad:#D98080;}}
*{{box-sizing:border-box}} html{{scroll-behavior:smooth;scroll-padding-top:80px}}
body{{margin:0;font:16px/1.6 ui-rounded,"SF Pro Rounded",-apple-system,BlinkMacSystemFont,Inter,system-ui,sans-serif;
color:var(--ink);background:radial-gradient(900px 520px at 12% -8%,var(--pink-wash),transparent 60%),
radial-gradient(820px 520px at 92% 4%,var(--lilac-wash),transparent 55%),var(--cream);-webkit-font-smoothing:antialiased}}
.wrap{{max-width:1080px;margin:0 auto;padding:0 24px 100px}}
header.hero{{text-align:center;padding:64px 20px 26px;max-width:820px;margin:0 auto}}
.eyebrow{{display:inline-block;font-size:12px;font-weight:800;letter-spacing:.14em;text-transform:uppercase;
color:var(--pink-ink);background:var(--card);border:1px solid var(--line);padding:7px 15px;border-radius:999px}}
.hero-pet{{font-size:54px;margin:14px 0 4px;filter:drop-shadow(0 8px 14px rgba(200,95,130,.20))}}
h1{{font-size:clamp(34px,6vw,54px);font-weight:800;letter-spacing:-.025em;margin:6px 0 10px;
background:linear-gradient(120deg,var(--ink) 30%,var(--pink-ink) 120%);-webkit-background-clip:text;background-clip:text;-webkit-text-fill-color:transparent}}
.sub{{font-size:18px;color:var(--ink2);max-width:640px;margin:0 auto 8px}}
.chips{{margin-top:14px;display:flex;gap:7px;justify-content:center;flex-wrap:wrap}}
.pill{{font-size:12px;font-weight:700;background:var(--sage-wash);color:#4f7a52;border:1px solid #cde6c4;border-radius:999px;padding:5px 11px}}
.northstar{{background:linear-gradient(135deg,var(--lilac-wash),var(--pink-wash));border:1px solid var(--line);
border-radius:20px;padding:22px 26px;margin:24px 0;text-align:center;font-size:19px;font-weight:600;color:#5a4f64}}
.northstar b{{color:var(--pink-ink)}}
.grid2{{display:grid;grid-template-columns:1fr 1fr;gap:18px;margin:18px 0}}
.box{{background:var(--card);border:1px solid var(--line);border-radius:18px;padding:20px 22px;box-shadow:0 6px 20px rgba(180,120,160,.07)}}
.box h4{{margin:0 0 10px;font-size:13px;letter-spacing:.1em;text-transform:uppercase;color:var(--pink-ink)}}
.box ul{{margin:0;padding-left:18px}} .box li{{margin:0 0 6px;color:#52465a}}
nav.toc{{position:sticky;top:14px;z-index:20;display:flex;gap:6px;flex-wrap:wrap;align-items:center;justify-content:center;
background:rgba(255,253,248,.85);backdrop-filter:blur(10px);border:1px solid var(--line);border-radius:999px;padding:9px 12px;margin:18px 0 30px;box-shadow:0 4px 16px rgba(180,120,160,.1)}}
nav.toc .l{{font-size:11px;font-weight:800;letter-spacing:.1em;text-transform:uppercase;color:var(--pink-ink);padding:0 6px}}
nav.toc a{{font-size:13px;font-weight:700;color:var(--ink2);text-decoration:none;padding:5px 11px;border-radius:999px}}
nav.toc a:hover{{background:var(--pink);color:#fff}}
h2.sec{{font-size:13px;letter-spacing:.12em;text-transform:uppercase;color:var(--pink-ink);margin:44px 0 8px;font-weight:800}}
.week{{background:var(--card);border:1px solid var(--line);border-radius:22px;padding:24px 26px 22px;margin:18px 0;box-shadow:0 8px 26px rgba(180,120,160,.09)}}
.week-head{{display:flex;align-items:center;gap:16px;margin-bottom:14px}}
.wnum{{flex:none;width:54px;height:54px;border-radius:16px;background:linear-gradient(135deg,var(--pink),var(--lilac));
color:#fff;font-weight:800;font-size:19px;display:grid;place-items:center;box-shadow:0 4px 12px rgba(200,95,130,.25)}}
.wdates{{font-size:12px;font-weight:700;color:var(--ink3);letter-spacing:.04em}}
.wtheme{{font-size:23px;font-weight:800;letter-spacing:-.01em;margin:2px 0 0}}
.milestone{{background:var(--butter-wash);border:1px solid #ecdc9b;border-radius:12px;padding:10px 14px;font-size:14.5px;margin-bottom:16px}}
.lanes{{display:grid;grid-template-columns:repeat(3,1fr);gap:14px}}
.lane{{border-radius:14px;padding:14px 15px;border:1px solid var(--line)}}
.lane.design{{background:var(--pink-wash);border-color:#ffd0e0}}
.lane.eng{{background:var(--sky-wash);border-color:#cfe7f1}}
.lane.prod{{background:var(--sage-wash);border-color:#cde6c4}}
.lane-h{{font-size:12.5px;font-weight:800;margin-bottom:8px;color:#5a4f64}}
.lane ul{{margin:0;padding-left:16px}} .lane li{{margin:0 0 6px;font-size:13.5px;color:#4d4350}}
.deps{{margin-top:14px;font-size:12.5px;color:var(--ink2)}} .deps-l{{font-weight:800;color:var(--lilac);text-transform:uppercase;letter-spacing:.08em;font-size:11px}}
.risks-row{{margin-top:12px;display:flex;flex-wrap:wrap;gap:8px;align-items:baseline}}
.risks-l{{font-size:11px;font-weight:800;text-transform:uppercase;letter-spacing:.08em;color:var(--warn)}}
.risk{{font-size:12.5px;background:#fff6ec;border:1px solid #f0dcc0;border-radius:9px;padding:5px 9px}}
.risk .rk{{font-weight:700;color:#9a6a2a}} .risk .mit{{color:var(--ink2)}}
.dod{{margin-top:14px;background:#f4fbf1;border:1px solid #d4ecd0;border-radius:12px;padding:11px 14px}}
.dod-l{{font-size:11px;font-weight:800;text-transform:uppercase;letter-spacing:.08em;color:var(--good)}}
.dod ul{{margin:6px 0 0;padding-left:18px}} .dod li{{font-size:13px;margin:0 0 4px}}
table{{width:100%;border-collapse:separate;border-spacing:0;background:var(--card);border:1px solid var(--line);border-radius:16px;overflow:hidden;margin:10px 0}}
th{{background:var(--pink-wash);text-align:left;font-size:11.5px;letter-spacing:.06em;text-transform:uppercase;color:var(--pink-ink);padding:11px 13px}}
td{{padding:11px 13px;border-top:1px solid var(--line);vertical-align:top;font-size:14px}}
.rtag{{font-weight:800;color:var(--pink-ink);white-space:nowrap}} .rwk{{color:var(--ink3);font-weight:700}}
.kc{{color:var(--ink2);font-style:italic}}
.sev{{font-size:11px;font-weight:800;border-radius:6px;padding:2px 8px;text-transform:uppercase}}
.sev-critical{{background:#fbe3e3;color:#b44}} .sev-high{{background:#fdeede;color:#b87420}}
.sev-medium{{background:#eef3ff;color:#5a6ea8}} .sev-low{{background:#eef7ea;color:#5f8a5a}}
.gates{{display:grid;grid-template-columns:1fr 1fr;gap:14px;margin:10px 0}}
.gate{{background:var(--lilac-wash);border:1px solid #e2d3ff;border-radius:16px;padding:16px 18px}}
.gate-w{{font-size:11px;font-weight:800;text-transform:uppercase;letter-spacing:.08em;color:#7a5bb5}}
.gate-q{{font-weight:700;margin:4px 0 8px}}
.gate-yn{{font-size:13px;margin:3px 0;color:#52465a}}
.gate-yn .yes{{font-weight:800;color:var(--good)}} .gate-yn .no{{font-weight:800;color:var(--bad)}}
footer{{text-align:center;color:var(--ink3);font-size:13px;margin-top:50px;border-top:1px dashed var(--line);padding-top:26px}}
@media(max-width:720px){{.lanes,.grid2,.gates{{grid-template-columns:1fr}}}}
</style></head>
<body><div class="wrap">
  <header class="hero">
    <span class="eyebrow">CPTO Build Plan · {len(weeks)} weeks</span>
    <div class="hero-pet">🐱</div>
    <h1>{esc(plan.get('title','Digital Pat — Build-Out Plan'))}</h1>
    <p class="sub">{esc(plan.get('subtitle',''))}</p>
    <div class="chips">{review_chips}</div>
  </header>

  <div class="northstar">★ <b>North star:</b> {esc(plan.get('northStar',''))}</div>

  <div class="grid2">
    <div class="box"><h4>Assumptions</h4><ul>{lis(plan.get('assumptions'))}</ul></div>
    <div class="box"><h4>Success metrics</h4><ul>{lis(plan.get('successMetrics'))}</ul></div>
  </div>

  <nav class="toc"><span class="l">Weeks</span>{toc}
    <a href="#releases">Releases</a><a href="#gates">Gates</a><a href="#risks">Risks</a></nav>

  <h2 class="sec">Week-by-week</h2>
  {''.join(week_cards)}

  <h2 class="sec" id="releases">Release timeline</h2>
  <table><thead><tr><th>Release</th><th>Week</th><th>Scope</th></tr></thead><tbody>{rel_rows}</tbody></table>

  {('<h2 class="sec" id="gates">Decision gates</h2><div class="gates">'+gates+'</div>') if gates else ''}

  <h2 class="sec" id="risks">Risk register</h2>
  <table><thead><tr><th>Severity</th><th>Risk</th><th>Mitigation</th><th>Kill criterion</th></tr></thead><tbody>{risk_rows}</tbody></table>

  {('<h2 class="sec">Open questions</h2><div class="box"><ul>'+lis(plan.get('openQuestions'))+'</ul></div>') if plan.get('openQuestions') else ''}

  <footer>Digital Pat · CPTO build-out plan · cute helper, not a tracker · drafted by design + eng + product, integrated & pressure-tested</footer>
</div></body></html>"""

open(OUT, "w", encoding="utf-8").write(HTML)
print("wrote", OUT, len(HTML), "bytes;", len(weeks), "weeks")
