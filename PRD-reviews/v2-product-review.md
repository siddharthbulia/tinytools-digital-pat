# Digital Pat v2 (Rooms) — Product Review

**Score:** 4 / 10
**One-sentence verdict:** A charming idea sitting on a graveyard — the cute-pet hook is real and underused, but the "ambient presence for friend groups" framing walks straight into the same cold-start + low-frequency-presence wall that killed Sqwiggle and starved Tandem, and the Pro split monetizes the wrong moment.

## Top 3 strengths
1. **The wedge art already exists and is genuinely differentiated.** Sneek (webcam stills), Tandem (virtual office), Discord (green dot) are all utilitarian or webcam-creepy. A *pixel-pet* presence layer is a real aesthetic wedge nobody in the graveyard had. The 22 bundled characters = a pre-built first room. That's a real cold-start asset most clones never have.
2. **The poke is a smarter daily hook than "presence."** Presence is passive and low-frequency (Tandem's own postmortem: presence felt "magical but low frequency"). The poke is an *action* with reciprocity — that's the thing that could actually create a daily loop. It's the strongest part of the PRD and it's underweighted.
3. **The privacy line is drawn correctly and early.** "Category mood only, never app/URL/keys" + no manager dashboards is the right call and pre-empts the surveillance smell that sinks workplace-presence tools. Good instinct.

## Top 5 weaknesses (severity: BLOCKER / MAJOR / MINOR)
1. **[BLOCKER] The product is worthless solo and the cold-start plan is a hand-wave.** §8 admits "presence is worthless solo" and the magic number is a ≥3-person room. But the entire activation plan is "seed with the founder's own team + invite codes + 'invite 2 friends.'" That is exactly what every dead presence app said. You are not shipping an app; you are shipping a *coordination problem* — every new user must drag 2+ specific people onto macOS, simultaneously online, who also install a desktop pet. Locket works because it's a phone widget with a 2-second add flow; you have macOS friction × group friction. Without a real answer here, nothing else matters.
2. **[MAJOR] Presence frequency is too low to retain, and you've cut the only things that raise it.** Tandem died on low-frequency presence even with calls/screenshare. You've explicitly cut chat, voice, video — so the *only* engagement primitive is the poke. If pokes get old in week 2 (they will, for most), there is no second loop. The "who missed you / streaks" feature is the actual retention mechanic and it's buried in Pro. That's backwards (see required changes).
3. **[MAJOR] The freemium line is on the wrong moment.** The wedge is "your friends live on your desktop + poke." The upgrade trigger should be the moment a group forms and wants to *be a group* — but the most natural group action (a private room for just your crew) is Pro, while the default room is free. You're charging the host at the exact moment of network formation, i.e. taxing virality. And "1 custom character free, describe-to-create Pro" gates *self-expression* — the thing that makes a 24-year-old screenshot and share. You're paywalling your own TikTok ad.
4. **[MAJOR] $4.99/mo is a subscription on a toy, and the v1 PRD already argued against this.** v1 explicitly says: "a recurring subscription would feel gross and kill conversion... one-time and impulse-priced... matches how the audience buys cosmetics." v2 reverses that with no justification. A cute pixel pet is a cosmetic/vibe purchase; $4.99/mo recurring on a poke toy will see brutal churn. Credits-for-AI is honest; the *subscription* framing is not.
5. **[MINOR/MAJOR] Defensibility of the social layer is thin.** The pet art + 22 characters are defensible (real cost, real taste). The presence + poke mechanic is not — it's a Supabase Realtime channel and a broadcast event. The moat is *the network inside each friend group* (switching cost = your crew is here), which only exists if cold-start is solved. So weakness #1 is also the defensibility story. No network, no moat.

## Required changes before approval
- **Pick the real wedge: it's the poke + the pet, not "presence."** Reframe the whole PRD around "the cutest way to say 'thinking of you' to your crew." Presence is the backdrop; poking is the product. This also de-risks the low-frequency problem.
- **Move "who missed you" + streaks into FREE.** Reciprocity and streaks (Snapstreak/Duolingo mechanics) are the retention engine. Locket's recap reels are free for the same reason. Don't paywall the loop.
- **Make private rooms FREE; gate on scale/cost instead.** Free = 1 private room for your crew. Pro = multiple rooms / large rooms. Charging the group-founder kills the network effect you're betting the whole pivot on.
- **Kill the $4.99/mo subscription. Go one-time + credit packs.** "Pat Pro $14.99 one-time" (custom-creation unlocked + cosmetics + multi-room) consistent with the v1 logic and the tinytools band, plus optional AI-character credit packs for the genuine per-image cost. Subscription on a pet is the death zone.
- **Write a real cold-start motion beyond "my own team."** One concrete viral surface: e.g. a poke received by a non-user opens a delightful web "someone's pixel buddy is bouncing — install to poke back" landing. Without an answer that doesn't depend on the founder's 10 friends, this is a demo, not a product.
- **Name the competitors in the PRD.** v2 mentions Sneek/Sqwiggle in risks but does no competitive analysis. Add the table below.

## Optional improvements
- Let custom-character generation (describe-to-create) be *the* shareable moment — generate, then auto-offer "share your buddy" outside the room. That's your acquisition loop AND your AI-cost monetization in one.
- Consider couples/pairs as the *real* beachhead, not 10-person teams. Locket's wedge was the 1:1 "Best Friend / Crush" widget. A 2-person room solves cold-start (drag *one* person) and presence frequency is far higher between two intimates than across a 10-person team.
- Seasonal cosmetic drops are the proven recurring-revenue pattern for this audience (better than a sub).

## Would I install + use this weekly?
**Conditional — leaning No for the team framing, Yes for the pairs framing.** I would install it to poke *one* specific person (partner/best friend) and keep it for the dumb-joy of the bouncing buddy. I would not sustain a 10-person team room past the novelty week — that's the Tandem failure mode, and I'd quietly quit it. Re-aim at pairs/tiny crews and the honest answer flips to Yes.

## Competitive analysis
| Competitor | What they do | Where they're weak | How we win |
|---|---|---|---|
| **Locket Widget** | iPhone home-screen photo widget from close friends; 20-friend cap, free, recap reels | Phone-only, photos = effort, no presence/ambient | Zero-effort auto presence + pixel charm; but learn their 1:1 wedge and free recap loop |
| **Sneek** | Always-on webcam stills of remote teammates, click-to-call | Webcam = the surveillance/creepy line; B2B; not cute | Pixel mood, never camera; affection-framed; consumer-cute |
| **Sqwiggle (dead)** | Webcam presence + instant video for remote teams | Shut down — webcam fatigue, low frequency | Non-camera, lightweight, poke loop over video |
| **Tandem (default-alive, ~250 cos)** | Virtual office, see who's around, 1-click call/screenshare | Postmortem: presence "magical but low frequency"; remote workers value autonomy over ambient togetherness | Don't sell presence; sell the poke + the joy. Consumer, not workplace |
| **Yo (dead)** | One-tap "Yo" notification | Pure novelty, no retained value | The poke must NOT be a Yo — pet + streaks + reciprocity give it a second loop |
| **Discord presence** | Status/green dot, rich presence | Cold, utilitarian, buried | Glanceable cozy room you *want* to look at |

## Pricing recommendation
**$14.99 one-time "Pat Pro"** (unlimited custom-character creation incl. describe-to-create, cosmetics, multiple/large rooms) **+ optional AI credit packs** ($4.99 / N generations) for the genuine gpt-image-1 cost. Kill the $4.99/mo subscription outright — it contradicts the v1 reasoning, churns hard on a toy, and a sub bill is the fastest way to make someone quit a pet. Keep the *first* private room and the streak/who-missed-you loop free so the network and the habit can form before you ever ask for money.

## Headline / wedge suggestion
**"Your people, on your desktop. Poke them. 🐱"** — lead with the pet + the poke (the thing that's differentiated and daily), not "ambient presence" (the thing that's in the graveyard). Subhead: *"Tiny pixel versions of your crew hang out in the corner of your screen — flick a 'miss you' at whoever's around."*
