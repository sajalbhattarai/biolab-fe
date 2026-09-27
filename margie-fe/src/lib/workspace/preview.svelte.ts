/**
 * Colour-vision state for an interface's root: the saved preview choice and
 * the data-* attributes workspace.css uses to recolour figures and add symbols.
 */

import { ui } from './ui.svelte';
import { recolourMatrix, type Vision } from './vision';

class Preview {
	/** The vision the whole page is shown as; 'typical' is off. */
	get vision(): Vision {
		return ui.prefs.previewVision;
	}
	set vision(v: Vision) {
		ui.update({ previewVision: v });
	}
}

export const preview = new Preview();

/** Whether figures and images are being recoloured now. */
export const recolouring = () => ui.prefs.recolour && !!recolourMatrix(ui.prefs.vision, ui.prefs.visionStrength);

/** Returns the data-* attributes to spread onto an interface's root element. */
export function visionAttrs(): Record<string, string | undefined> {
	return {
		'data-vision': ui.prefs.vision,
		'data-recolour': recolouring() ? '' : undefined,
		'data-preview': preview.vision !== 'typical' ? preview.vision : undefined,
		'data-marks': ui.prefs.marks ? '' : undefined
	};
}
