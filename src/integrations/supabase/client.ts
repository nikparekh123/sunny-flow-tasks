// Supabase client. Uses cookie-based session storage scoped to the parent
// domain (.sunnyfi.co) so logging in once on sunnyfi.co auto-signs the user
// in across todos.sunnyfi.co / any other subdomain that uses the same key.
import { createClient } from '@supabase/supabase-js';
import type { Database } from './types';
import { cookieStorage } from './cookieStorage';

const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
const SUPABASE_PUBLISHABLE_KEY = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

export const supabase = createClient<Database>(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: {
    storage: cookieStorage,
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
    flowType: 'pkce',
  },
});
