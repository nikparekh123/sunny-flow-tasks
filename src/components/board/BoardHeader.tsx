export function BoardHeader() {
  return (
    <div
      className="px-5 md:px-7 pt-4 pb-[14px]"
      style={{ borderBottom: '1px solid var(--owl-line)' }}
    >
      <h1
        style={{
          fontSize: 'clamp(26px, 3.6vw, 36px)',
          fontWeight: 300,
          letterSpacing: '-1.2px',
          lineHeight: 1,
          color: 'var(--owl-text-primary)',
        }}
      >
        Team <b style={{ fontWeight: 700 }}>to do's</b>
      </h1>
    </div>
  );
}
