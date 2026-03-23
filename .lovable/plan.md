

## Plan: Fix Infinite Loading State

### Root Cause

In `src/hooks/useAuth.tsx`, the `onAuthStateChange` callback does async database work (fetching/creating team member). If any of those calls throw an error, execution stops before reaching `setLoading(false)` on line 53. The app permanently shows "Loading…".

### Fix

**`src/hooks/useAuth.tsx`** — Wrap the entire `onAuthStateChange` callback body in a try/catch/finally block, with `setLoading(false)` in the `finally`. This guarantees loading ends even if the team member queries fail.

```ts
onAuthStateChange(async (_event, session) => {
  try {
    const u = session?.user ?? null;
    setUser(u);
    if (u) {
      // ... existing team member fetch/create logic
    } else {
      setMember(null);
    }
  } catch (err) {
    console.error('Auth state error:', err);
    setMember(null);
  } finally {
    setLoading(false);
  }
});
```

### Files Changed

| File | Change |
|------|--------|
| `src/hooks/useAuth.tsx` | Add try/catch/finally around auth callback to guarantee `setLoading(false)` runs |

