/** The statement a user types to open installation: it confirms the upstream licences and MARGIE's terms. */
export const INSTALL_STATEMENT = 'I have the necessary licenses for the upstream tools and accept the license terms agreement of MARGIE.';

/** The text as compared: exactly as typed, apart from spaces at either end. */
export const normaliseStatement = (s: unknown) => String(s ?? '').trim();
