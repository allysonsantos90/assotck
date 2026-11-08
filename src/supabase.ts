import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL?.trim();
const key = (
  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY ||
  import.meta.env.VITE_SUPABASE_ANON_KEY
)?.trim();

const validUrl = Boolean(
  url &&
  !url.includes('YOUR-PROJECT') &&
  /^https?:\/\//i.test(url)
);

export const isConfigured = Boolean(validUrl && key && !key.startsWith('YOUR_'));

export const supabase = isConfigured
  ? createClient(url!, key!, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
      },
    })
  : null;
