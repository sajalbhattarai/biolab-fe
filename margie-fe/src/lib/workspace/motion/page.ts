import { afterNavigate, onNavigate } from '$app/navigation';
import { ui } from '../ui.svelte';

/**
 * Animates page changes with view transitions: only `mo-main` fades and rises,
 * and each new page scrolls `scroller` to the top; same-page query changes are
 * skipped. Runs during a layout component's setup.
 */
export function pageMotion(scroller: () => HTMLElement | null | undefined) {
	onNavigate((nav) => {
		if (!document.startViewTransition || ui.motion === 'off' || !nav.to || nav.from?.url.pathname === nav.to.url.pathname) return;
		document.documentElement.style.setProperty('--vt-dur', `${ui.ms(340)}ms`);
		return new Promise((resolve) => {
			document.startViewTransition(async () => {
				resolve();
				await nav.complete;
			});
		});
	});
	afterNavigate((nav) => {
		if (nav.type === 'enter' || nav.type === 'popstate' || nav.to?.url.hash) return;
		if (nav.from?.url.pathname === nav.to?.url.pathname) return;
		scroller()?.scrollTo({ top: 0, behavior: 'instant' });
	});
}
