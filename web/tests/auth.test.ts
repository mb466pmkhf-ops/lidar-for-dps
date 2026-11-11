import { describe, expect, it } from 'vitest';
import { challengeFor, pkcePair } from '../src/sync/oauth';
import { authMessage, SupabaseClient } from '../src/sync/supabase';

describe('sign-in helpers', () => {
  it('makes the RFC 7636 PKCE challenge', async () => {
    expect(await challengeFor('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk')).toBe('E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM');
    const { verifier, challenge } = await pkcePair();
    expect(verifier).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(challenge).toBe(await challengeFor(verifier));
  });

  it('builds the provider URL with PKCE and the redirect', () => {
    const c = new SupabaseClient({ url: 'https://x.supabase.co/', anonKey: 'k' });
    const u = new URL(c.authorizeURL('google', 'http://127.0.0.1:53682/auth-callback', 'abc'));
    expect(u.origin + u.pathname).toBe('https://x.supabase.co/auth/v1/authorize');
    expect(u.searchParams.get('provider')).toBe('google');
    expect(u.searchParams.get('redirect_to')).toBe('http://127.0.0.1:53682/auth-callback');
    expect(u.searchParams.get('code_challenge')).toBe('abc');
    expect(u.searchParams.get('code_challenge_method')).toBe('s256');
  });

  it('explains auth errors in plain words', () => {
    expect(authMessage({ error_code: 'email_not_confirmed', msg: 'Email not confirmed' }, 400)).toMatch(/Confirm your email/);
    expect(authMessage({ error_code: 'invalid_credentials' }, 400)).toBe('Wrong email or password.');
    expect(authMessage({ msg: 'Something else' }, 400)).toBe('Something else');
    expect(authMessage({}, 500)).toBe('Sign-in failed (500)');
  });
});
