/**
 * Holds the base path of the interface on screen so shared parts link inside
 * it; each shell sets it once.
 */

let path = $state('/crisp');

export const uiBase = {
	get path() {
		return path;
	},
	set(to: string) {
		path = to;
	},
	/** `uiBase.to('/results')` -> `/app/results`, `/crisp/results`, ... */
	to(rest: string) {
		return path + rest;
	}
};
