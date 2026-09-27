/**
 * Svelte action that slides a `.mo-thumb` highlight behind a group's selected
 * item; the group gets `mo-has-thumb` (see motion.css).
 */
export function thumb(node: HTMLElement) {
	const el = document.createElement('span');
	el.className = 'mo-thumb';
	el.setAttribute('aria-hidden', 'true');
	node.append(el);
	node.classList.add('mo-has-thumb');
	let placed = false;

	const place = () => {
		const sel = node.querySelector<HTMLElement>(
			':scope > [aria-selected="true"], :scope > [aria-checked="true"], :scope > [aria-current="page"]'
		);
		if (!sel || !sel.offsetWidth) {
			el.style.opacity = '0';
			placed = false;
			return;
		}
		// The first placement (and after being hidden) is instant; then it slides.
		if (!placed) el.style.transition = 'none';
		el.style.opacity = '1';
		el.style.width = `${sel.offsetWidth}px`;
		el.style.height = `${sel.offsetHeight}px`;
		el.style.transform = `translate(${sel.offsetLeft}px, ${sel.offsetTop}px)`;
		if (!placed) {
			void el.offsetWidth;
			el.style.transition = '';
			placed = true;
		}
	};

	const mo = new MutationObserver(place);
	mo.observe(node, { subtree: true, childList: true, characterData: true, attributes: true, attributeFilter: ['aria-selected', 'aria-checked', 'aria-current'] });
	const ro = new ResizeObserver(place);
	ro.observe(node);
	place();
	document.fonts?.ready.then(place);

	return {
		destroy() {
			mo.disconnect();
			ro.disconnect();
			el.remove();
		}
	};
}
