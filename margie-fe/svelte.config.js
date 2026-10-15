import adapterNode from '@sveltejs/adapter-node';
import adapterStatic from '@sveltejs/adapter-static';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

// VITE_HOSTED=1 builds the static site (see src/lib/hosted.ts); otherwise the
// node server the desktop app and the `margie` launcher run.
const hosted = process.env.VITE_HOSTED === '1';

/** @type {import('@sveltejs/kit').Config} */
const config = {
	// Consult https://svelte.dev/docs/kit/integrations
	// for more information about preprocessors
	preprocess: vitePreprocess(),

	kit: {
		adapter: hosted ? adapterStatic({ fallback: 'index.html', strict: false }) : adapterNode()
	}
};

export default config;
