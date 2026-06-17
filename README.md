# Digital Pat 🐱

A tiny pixel-art companion that lives on your Mac. It quietly reacts to whatever app you're in,
purrs when you pat it, plays around your screen — and it's **multiplayer**: add a friend with an
invite code and your pixel selves live on each other's desktops in real time.

**Download (free, signed & notarized):** https://digital-pat.vercel.app

- Native **Swift / AppKit** menu-bar app (`LSUIElement`), floating borderless pet panels.
- Reacts to the frontmost app (and, in the browser, the active tab's *domain* — never the page/content).
- **24 bundled characters**; generate your own from a photo or text (no API key needed).
- **Friend graph** (mutual 1:1, private — only friends see you) over **Supabase Realtime**.
- **Chipkoo / Attract / Push** cursor modes that sync to friends.
- Self-updates via **Sparkle**.

## Layout

```
swift-src/        SwiftPM executable + build.sh (universal, sign, notarize, staple, DMG)
characters/       bundled sprite sets (one folder per character: <mood>.png + per-mood blinks)
design/           sprite-generation scripts (gpt-image-1 → pixelate) + concepts
supabase/         schema.sql + friends.sql (friend graph, RPCs, RLS) + Edge Functions
website/          marketing site + appcast.xml (deployed to Vercel)
test-harness/     multi-device integration tests (real SDK, N anonymous clients vs live Supabase)
```

## Build

Requires Xcode toolchain + an Apple Developer ID for signing/notarization. Copy your creds into
`apps/digital-pat/.env` (`APPLE_ID`, `APPLE_PASSWORD`, `APPLE_TEAM_ID`, `APPLE_IDENTITY`) — this file
is gitignored. Then:

```sh
cd swift-src
VERSION=2.8.1 ./build.sh            # universal binary → .app → sign → notarize → staple → DMG
./build.sh --dev                    # unsigned local build, no notarization
```

The embedded Supabase **anon** key + Edge Function URL are public by design (RLS-protected); no private
keys live in this repo.

## License

© Mili Software Inc. All rights reserved.
