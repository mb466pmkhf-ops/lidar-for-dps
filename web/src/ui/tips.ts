// Gesture tips are shown until the user dismisses them once (Docs/LOOK.md: explain once, not
// on every visit). Remembered per browser.
import { useState } from 'react';

export function useTip(key: string): [seen: boolean, hide: () => void] {
  const storageKey = `framescan.tip.${key}`;
  const [seen, setSeen] = useState(() => { try { return localStorage.getItem(storageKey) === '1'; } catch { return false; } });
  const hide = () => { setSeen(true); try { localStorage.setItem(storageKey, '1'); } catch { /* private mode */ } };
  return [seen, hide];
}
