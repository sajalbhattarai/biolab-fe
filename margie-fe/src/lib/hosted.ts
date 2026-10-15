/**
 * Hosted build (VITE_HOSTED=1): the interface is served as static files from a
 * website and works only with a cluster through MARGIE's API at VITE_PUBLIC_API_URL.
 * There is no local pipeline, no start page and no server routes (routes/api) on
 * the site, so anything they provided is either hidden or kept in the browser.
 * The desktop app and the terminal launcher build without it and keep both modes.
 */
export const HOSTED = import.meta.env.VITE_HOSTED === '1';
