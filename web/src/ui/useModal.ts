import { useEffect, useRef } from 'react';

const FOCUSABLE = 'button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

/** Keyboard behaviour every dialog needs: Escape closes it (and only it: the planner behind
 *  keeps its selection), Tab stays inside it, focus moves in when it opens and goes back to
 *  where it was when it closes. Put the returned ref on the element with role="dialog". */
export function useModal<T extends HTMLElement>(onClose: () => void) {
  const ref = useRef<T>(null);
  const close = useRef(onClose);
  close.current = onClose;

  useEffect(() => {
    const before = document.activeElement as HTMLElement | null;
    const box = ref.current;
    if (box && !box.contains(document.activeElement)) {
      // An autofocus field wins; otherwise the first control, or the dialog itself.
      const first = box.querySelector<HTMLElement>('[autofocus]') ?? box.querySelector<HTMLElement>(FOCUSABLE);
      if (first) first.focus();
      else { box.tabIndex = -1; box.focus(); }
    }
    const onKey = (e: KeyboardEvent) => {
      const el = ref.current;
      if (!el) return;
      // Only the top dialog answers when one opens another.
      const dialogs = document.querySelectorAll('[role="dialog"][aria-modal="true"]');
      if (dialogs[dialogs.length - 1] !== el) return;
      if (e.key === 'Escape') {
        e.preventDefault();
        e.stopImmediatePropagation();
        close.current();
        return;
      }
      if (e.key !== 'Tab') return;
      const items = [...el.querySelectorAll<HTMLElement>(FOCUSABLE)].filter(x => x.offsetParent !== null || x === document.activeElement);
      if (!items.length) { e.preventDefault(); return; }
      const first = items[0], last = items[items.length - 1];
      const active = document.activeElement;
      if (e.shiftKey && (active === first || !el.contains(active))) { e.preventDefault(); last.focus(); }
      else if (!e.shiftKey && (active === last || !el.contains(active))) { e.preventDefault(); first.focus(); }
    };
    // Capture phase on window runs before the planner's own Escape handler.
    window.addEventListener('keydown', onKey, true);
    return () => {
      window.removeEventListener('keydown', onKey, true);
      if (before && document.contains(before)) before.focus();
    };
  }, []);

  return ref;
}
