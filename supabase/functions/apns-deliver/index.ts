/**
 * apns-deliver — drain undelivered alert_dispatch rows and send
 * them to Apple Push Notification service.
 *
 * Auth model: ES256-signed JWT per Apple's token-based APNs
 * authentication. The .p8 key contents, Key ID, and Team ID live
 * in Supabase Function secrets — never committed to the repo.
 *
 * Required secrets (Supabase → Edge Functions → Secrets):
 *   APNS_AUTH_KEY      — full .p8 contents incl. BEGIN/END lines
 *   APNS_KEY_ID        — 10-char Key ID, e.g. J483K9UU6U
 *   APNS_TEAM_ID       — 10-char Team ID, e.g. AR5LF7RNCP
 *   APNS_BUNDLE_ID     — e.g. com.sunnyfi.Sunnyfi
 *
 * For every undelivered alert_dispatch row, this function:
 *   1. Looks up every push_devices row matching the bundle
 *   2. POSTs the APNs payload to each token (production AND
 *      sandbox URLs, routing per device.environment)
 *   3. Marks alert_dispatch.delivered_at = now() once at least
 *      one device succeeded
 *
 * Idempotency: alerts that already have delivered_at are skipped.
 * Dedup against duplicate alerts is the dispatcher's job
 * (alert_dispatch.dedup_key UNIQUE).
 *
 * Cron cadence: every 60s. APNs is async — we don't wait long.
 */
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

// ─── APNs config ────────────────────────────────────────────────
const APNS_HOSTS = {
  production: 'https://api.push.apple.com',
  sandbox:    'https://api.sandbox.push.apple.com',
};

// ─── JWT cache (1 token per ~50 min, Apple max 60 min) ─────────
let cachedToken: { jwt: string; mintedAt: number } | null = null;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const teamId   = Deno.env.get('APNS_TEAM_ID');
  const keyId    = Deno.env.get('APNS_KEY_ID');
  const authKey  = Deno.env.get('APNS_AUTH_KEY');
  const bundleId = Deno.env.get('APNS_BUNDLE_ID');
  if (!teamId || !keyId || !authKey || !bundleId) {
    return new Response(
      JSON.stringify({ error: 'APNS_* env vars not set' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }

  // 1) Pull pending alerts (cap per run so we don't time out).
  const { data: alerts, error: alertsErr } = await supabase
    .from('alert_dispatch')
    .select('id, category, ticker, title, body, deep_link, meta')
    .is('delivered_at', null)
    .order('created_at', { ascending: true })
    .limit(50);
  if (alertsErr) {
    return new Response(
      JSON.stringify({ error: `alert_dispatch query: ${alertsErr.message}` }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
  if (!alerts || alerts.length === 0) {
    return new Response(JSON.stringify({ ok: true, sent: 0 }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  // 2) Pull every registered device for this bundle.
  const { data: devices, error: devErr } = await supabase
    .from('push_devices')
    .select('token, environment, bundle_id')
    .eq('bundle_id', bundleId);
  if (devErr) {
    return new Response(
      JSON.stringify({ error: `push_devices query: ${devErr.message}` }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
  if (!devices || devices.length === 0) {
    // No devices registered yet — nothing to do, but the alerts
    // stay un-delivered so they'll be picked up later if a device
    // appears.
    return new Response(JSON.stringify({ ok: true, sent: 0, note: 'no devices registered' }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  // 3) Mint a JWT (or reuse cached).
  const jwt = await getAPNsJWT({ teamId, keyId, authKey });

  // 4) Send each alert to each device.
  let totalSent = 0;
  let totalFailed = 0;
  const failures: { token_prefix: string; status: number; reason?: string }[] = [];
  const deliveredAlertIDs: string[] = [];

  for (const alert of alerts) {
    let anyOK = false;
    for (const dev of devices) {
      const host = APNS_HOSTS[dev.environment as 'production' | 'sandbox'];
      if (!host) continue;
      const payload = {
        aps: {
          alert: {
            title: alert.title,
            body: alert.body ?? '',
          },
          sound: 'default',
          'thread-id': alert.category,           // groups related alerts in Notification Center
          'mutable-content': 1,
        },
        // Custom data the iOS app uses for deep-linking.
        category: alert.category,
        ticker: alert.ticker ?? null,
        deep_link: alert.deep_link ?? null,
        alert_id: alert.id,
      };
      try {
        const res = await fetch(`${host}/3/device/${dev.token}`, {
          method: 'POST',
          headers: {
            'authorization': `bearer ${jwt}`,
            'apns-topic': bundleId,
            'apns-push-type': 'alert',
            'apns-priority': '10',
            'content-type': 'application/json',
          },
          body: JSON.stringify(payload),
        });
        if (res.ok) {
          totalSent++;
          anyOK = true;
        } else {
          totalFailed++;
          const reason = await res.text().catch(() => '');
          failures.push({ token_prefix: dev.token.slice(0, 8), status: res.status, reason });
          // 410 Gone = device unregistered. Remove it so we don't
          // keep wasting requests.
          if (res.status === 410) {
            await supabase.from('push_devices').delete().eq('token', dev.token);
          }
        }
      } catch (err) {
        totalFailed++;
        failures.push({ token_prefix: dev.token.slice(0, 8), status: 0, reason: String(err) });
      }
    }
    if (anyOK) deliveredAlertIDs.push(alert.id);
  }

  // 5) Mark delivered for whatever succeeded.
  if (deliveredAlertIDs.length > 0) {
    await supabase
      .from('alert_dispatch')
      .update({ delivered_at: new Date().toISOString() })
      .in('id', deliveredAlertIDs);
  }

  return new Response(
    JSON.stringify({
      ok: true,
      alerts: alerts.length,
      devices: devices.length,
      sent: totalSent,
      failed: totalFailed,
      delivered_alerts: deliveredAlertIDs.length,
      failures: failures.slice(0, 10),
    }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
  );
});

// ─── JWT signing ────────────────────────────────────────────────
//
// ES256 (ECDSA with SHA-256, curve P-256). Apple requires this
// exact algorithm. The .p8 file is a PEM-encoded EC private key
// — we parse it into a CryptoKey via SubtleCrypto.importKey.
//
async function getAPNsJWT(opts: {
  teamId: string;
  keyId: string;
  authKey: string;
}): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  // Reuse cached token if < 50 min old. Apple max age is 60 min.
  if (cachedToken && (now - Math.floor(cachedToken.mintedAt / 1000)) < 50 * 60) {
    return cachedToken.jwt;
  }

  const header = { alg: 'ES256', kid: opts.keyId, typ: 'JWT' };
  const payload = { iss: opts.teamId, iat: now };

  const enc = (obj: unknown) =>
    base64UrlEncode(new TextEncoder().encode(JSON.stringify(obj)));

  const unsigned = `${enc(header)}.${enc(payload)}`;

  const key = await importECPrivateKey(opts.authKey);
  const sig = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    new TextEncoder().encode(unsigned),
  );
  const sigB64 = base64UrlEncode(new Uint8Array(sig));

  const jwt = `${unsigned}.${sigB64}`;
  cachedToken = { jwt, mintedAt: Date.now() };
  return jwt;
}

function base64UrlEncode(data: Uint8Array): string {
  const s = btoa(String.fromCharCode(...data));
  return s.replace(/=+$/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

async function importECPrivateKey(pem: string): Promise<CryptoKey> {
  // Strip PEM wrapper + whitespace, base64-decode to raw DER bytes.
  const body = pem
    .replace(/-----BEGIN [^-]+-----/g, '')
    .replace(/-----END [^-]+-----/g, '')
    .replace(/\s+/g, '');
  const binStr = atob(body);
  const buf = new Uint8Array(binStr.length);
  for (let i = 0; i < binStr.length; i++) buf[i] = binStr.charCodeAt(i);
  return crypto.subtle.importKey(
    'pkcs8',
    buf,
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  );
}
