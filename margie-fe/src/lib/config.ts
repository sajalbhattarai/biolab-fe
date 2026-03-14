/**
 * Environment configuration for API URL
 */

import { browser } from '$app/environment';

// Determine API URL based on environment
export const API_URL = browser && typeof window !== 'undefined'
	? (import.meta.env.VITE_PUBLIC_API_URL as string ||
	   (['localhost', '127.0.0.1', '0.0.0.0'].includes(window.location.hostname)
	      ? 'http://localhost:8000'
	      : ''))
	: '';
