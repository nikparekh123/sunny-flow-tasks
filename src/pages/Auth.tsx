/**
 * No more pincode entry. Auth is handled by sunnyfi.co (same Supabase
 * project + magic links). When the user lands here without a session,
 * we send them back to sunnyfi.co's login.
 */

const SUNNYFI_LOGIN_URL = 'https://sunnyfi.co';

export default function Auth() {
  const here = typeof window !== 'undefined' ? window.location.href : 'https://todos.sunnyfi.co';
  const loginHref = `${SUNNYFI_LOGIN_URL}?next=${encodeURIComponent(here)}`;

  return (
    <div
      className="flex min-h-screen items-center justify-center"
      style={{ backgroundColor: 'var(--owl-page)' }}
    >
      <div className="w-full max-w-sm px-6 text-center">
        <div className="flex items-center justify-center gap-[9px] mb-6">
          <div
            style={{
              width: 18,
              height: 18,
              background: 'var(--owl-neon)',
              borderRadius: 2,
              transform: 'rotate(10deg)',
              boxShadow: '0 0 0 2px rgba(210,230,50,0.15)',
            }}
          />
          <div
            className="text-[14px] font-bold tracking-[0.5px]"
            style={{ color: 'var(--owl-text-primary)' }}
          >
            S To dos
          </div>
        </div>

        <h1
          style={{
            fontSize: 22,
            fontWeight: 300,
            letterSpacing: '-0.5px',
            color: 'var(--owl-text-primary)',
          }}
        >
          Sign in at <b style={{ fontWeight: 600 }}>sunnyfi.co</b>
        </h1>
        <p
          className="mt-3"
          style={{ fontSize: 13, color: 'var(--owl-text-muted)', lineHeight: 1.55 }}
        >
          Use your Sunnyfi login. Once you're in, your task app session
          carries over automatically.
        </p>

        <a
          href={loginHref}
          className="inline-flex items-center justify-center gap-2 mt-8 rounded-lg transition-colors"
          style={{
            fontSize: 13,
            fontWeight: 500,
            padding: '10px 18px',
            background: 'var(--owl-neon)',
            color: '#0a2828',
            textDecoration: 'none',
            border: 'none',
          }}
        >
          Continue to sunnyfi.co →
        </a>

        <p
          className="mt-6"
          style={{
            fontFamily: 'var(--owl-font-mono)',
            fontSize: 10,
            color: 'var(--owl-text-label)',
            letterSpacing: '0.5px',
          }}
        >
          Already signed in? Refresh this page.
        </p>
      </div>
    </div>
  );
}
