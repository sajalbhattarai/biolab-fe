/**
 * Environment configuration for API URL
 *
 * In SvelteKit, PUBLIC_ env vars are available at build time and runtime
 * We'll use this to configure the API endpoint for different environments
 */

import { browser } from '$app/environment';

// Get the API URL from environment or use defaults
export const API_URL = browser && typeof window !== 'undefined'
	? (import.meta.env.VITE_PUBLIC_API_URL as string ||
	   (window.location.hostname === 'localhost' ? 'http://localhost:8000' : ''))
	: '';

// Export for use in server-side code
export const getApiUrl = (): string => {
	return API_URL;
};
