/**
 * Cookie-backed storage adapter for Supabase Auth, scoped to the parent
 * domain so sessions are shared across subdomains (sunnyfi.co + any
 * todos.sunnyfi.co / *.sunnyfi.co subdomain). Falls back to first-party
 * cookies for localhost / IP dev so it still works locally.
 *
 * Use as: createClient(url, key, { auth: { storage: cookieStorage } }).
 */

function getDomain(): string | undefined {
  const host = typeof window !== 'undefined' ? window.location.hostname : '';
  // localhost / IP-based dev: omit Domain so the cookie is scoped to origin.
  if (!host || host === 'localhost' || /^[\d.]+$/.test(host)) return undefined;
  // Any *.sunnyfi.co host shares the parent domain. For arbitrary multi-level
  // domains, this takes the last two labels.
  const parts = host.split('.');
  if (parts.length < 2) return undefined;
  return '.' + parts.slice(-2).join('.');
}

export const cookieStorage = {
  getItem(key: string): string | null {
    if (typeof document === 'undefined') return null;
    const cookies = document.cookie ? document.cookie.split('; ') : [];
    for (const c of cookies) {
      const eq = c.indexOf('=');
      if (eq < 0) continue;
      const k = c.slice(0, eq);
      if (k === key) {
        try {
          return decodeURIComponent(c.slice(eq + 1));
        } catch {
          return c.slice(eq + 1);
        }
      }
    }
    return null;
  },

  setItem(key: string, value: string): void {
    if (typeof document === 'undefined') return;
    const domain = getDomain();
    const parts = [
      `${key}=${encodeURIComponent(value)}`,
      'path=/',
      'max-age=31536000', // 1 year — Supabase refresh-token rotation handles real expiry
      'SameSite=Lax',
    ];
    if (typeof location !== 'undefined' && location.protocol === 'https:') {
      parts.push('Secure');
    }
    if (domain) parts.push(`Domain=${domain}`);
    document.cookie = parts.join('; ');
  },

  removeItem(key: string): void {
    if (typeof document === 'undefined') return;
    const domain = getDomain();
    const parts = [`${key}=`, 'path=/', 'max-age=0'];
    if (domain) parts.push(`Domain=${domain}`);
    document.cookie = parts.join('; ');
  },
};
