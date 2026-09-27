/**
 * The licence statement typed to accept the gated tools; it matches
 * LICENCE_REQUIRED_STATEMENT in processing/scripts/shared/licence-gate.sh and margie-build.
 */

export const LICENCE_STATEMENT =
	'I accept that I am using these tools for non-commercial purposes and have received all permissions from the upstream developers.';

export const LICENCE_LEGAL_NOTICE =
	'This is a legally binding agreement. Once you accept, your use of these tools and their databases is entirely your own responsibility.';

/** Normalises as licence-gate.sh does: lower case, single spaces, no final full stop. */
const normalise = (s: string) =>
	s
		.toLowerCase()
		.replace(/\s+/g, ' ')
		.trim()
		.replace(/\.$/, '');

export const statementMatches = (typed: string | null | undefined) => !!typed && normalise(typed) === normalise(LICENCE_STATEMENT);
