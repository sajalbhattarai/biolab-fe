import { HOSTED } from '$lib/hosted';

// A hosted build is a static single-page app: the client renders every page.
export const ssr = !HOSTED;
export const prerender = false;
