'use client';
// SPDX-License-Identifier: AGPL-3.0-only
// The one script the small-screen menu has, and it renders nothing: the menu is
// the browser's own `<details>` and every entry is a real link, so tapping one
// navigates with this file absent. What it adds is the thing markup cannot do -
// close the panel behind the reader, which matters for `/#features`, where the
// browser stays on the page and the open panel would otherwise sit over the
// section that was asked for. The same shape as TocSpy: one delegated listener,
// no `preventDefault`, so the navigation itself is still the browser's.
import { useEffect } from 'react';

export function HeaderMenuClose() {
  useEffect(() => {
    function onClick(event: MouseEvent) {
      // Anything but a plain left click belongs to the browser: a new tab, a
      // new window, a saved link - and the panel stays open with the page.
      if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      const target = event.target;
      const link = target instanceof Element ? target.closest('a') : null;
      link?.closest('details[data-header-menu][open]')?.removeAttribute('open');
    }
    document.addEventListener('click', onClick);
    return () => {
      document.removeEventListener('click', onClick);
    };
  }, []);

  return null;
}
