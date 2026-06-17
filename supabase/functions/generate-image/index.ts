// Digital Pat — server-side OpenAI image proxy (HARDENED for v2).
// The app sends a base64 PNG + a prompt; this function adds the OpenAI key
// (held as a Supabase secret) and calls gpt-image-1's /images/edits endpoint,
// returning the generated PNG as base64. So end users never enter an API key.
//
// Auth: deployed with --verify-jwt, so the platform requires a valid Supabase user
// JWT (from anonymous auth). We extract the user's uid (sub) and enforce a per-user
// DAILY cap via the consume_generation() RPC — this is what actually protects the
// OpenAI card (the embedded shared secret is extractable and only deters casual abuse).
//
// Secrets:
//   OPENAI_API_KEY    — the OpenAI key
//   PAT_SHARED_SECRET — optional shared token (x-pat-secret), defense in depth
//   PAT_DAILY_GEN_CAP — max image calls/user/day (default 60 ≈ ~3 characters)
// Auto-injected by Supabase: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
//
// Deploy:  supabase functions deploy generate-image --project-ref <ref>   (verify-jwt ON)

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, x-pat-secret, apikey",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

// Decode the `sub` (user id) from a JWT without verifying (the platform already verified it).
function uidFromJWT(auth: string | null): string | null {
  if (!auth) return null;
  const tok = auth.replace(/^Bearer\s+/i, "");
  const parts = tok.split(".");
  if (parts.length !== 3) return null;
  try {
    const pad = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(atob(pad + "=".repeat((4 - pad.length % 4) % 4)));
    return payload.sub ?? null;
  } catch {
    return null;
  }
}

// Atomically check+increment the caller's daily generation count via the service role.
async function withinDailyCap(uid: string, cap: number): Promise<boolean> {
  const url = Deno.env.get("SUPABASE_URL");
  const svc = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !svc) return true; // fail open only if platform env missing (shouldn't happen)
  const r = await fetch(`${url}/rest/v1/rpc/consume_generation`, {
    method: "POST",
    headers: { "Content-Type": "application/json", apikey: svc, Authorization: `Bearer ${svc}` },
    body: JSON.stringify({ p_uid: uid, p_cap: cap }),
  });
  if (!r.ok) return false;
  return (await r.json()) === true;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const sharedSecret = Deno.env.get("PAT_SHARED_SECRET");
  if (sharedSecret && req.headers.get("x-pat-secret") !== sharedSecret) {
    return json({ error: "unauthorized" }, 401);
  }

  // identify the user from the (platform-verified) JWT and enforce the daily cap
  const uid = uidFromJWT(req.headers.get("Authorization"));
  if (!uid) return json({ error: "sign-in required" }, 401);
  const cap = parseInt(Deno.env.get("PAT_DAILY_GEN_CAP") ?? "60", 10);
  if (!(await withinDailyCap(uid, cap))) {
    return json({ error: "daily generation limit reached — try again tomorrow" }, 429);
  }

  const key = Deno.env.get("OPENAI_API_KEY");
  if (!key) return json({ error: "server missing OPENAI_API_KEY" }, 500);

  let payload: {
    image?: string; prompt?: string;
    size?: string; quality?: string; background?: string;
  };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }
  const { image, prompt } = payload;
  if (!image || !prompt) return json({ error: "image (base64) and prompt are required" }, 400);

  let bytes: Uint8Array;
  try {
    bytes = Uint8Array.from(atob(image), (c) => c.charCodeAt(0));
  } catch {
    return json({ error: "image must be base64-encoded PNG" }, 400);
  }

  const form = new FormData();
  form.append("model", "gpt-image-1");
  form.append("prompt", prompt);
  form.append("size", payload.size ?? "1024x1024");
  form.append("quality", payload.quality ?? "medium");
  form.append("background", payload.background ?? "transparent");
  form.append("n", "1");
  form.append("image", new Blob([bytes], { type: "image/png" }), "photo.png");

  // up to 3 attempts; image gens occasionally hiccup
  let lastErr = "";
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const r = await fetch("https://api.openai.com/v1/images/edits", {
        method: "POST",
        headers: { Authorization: `Bearer ${key}` },
        body: form,
      });
      const data = await r.json();
      if (!r.ok) { lastErr = JSON.stringify(data?.error ?? data).slice(0, 300); continue; }
      const b64 = data?.data?.[0]?.b64_json;
      if (!b64) { lastErr = "no image in response"; continue; }
      return json({ b64_json: b64 });
    } catch (e) {
      lastErr = String(e);
    }
  }
  return json({ error: `openai failed: ${lastErr}` }, 502);
});
