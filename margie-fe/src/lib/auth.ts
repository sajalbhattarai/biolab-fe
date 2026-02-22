/**
 * Auth token storage and header utilities.
 *
 * All pages import authHeaders() to inject Authorization: Bearer <token>
 * into fetch calls. No page should read localStorage directly.
 *
 * NOTE: all functions read/write localStorage which is only available in the
 * browser. Do not call them at module level — only inside onMount or event
 * handlers.
 */

const TOKEN_KEY = 'bsp_token';

export function getToken(): string | null {
    return localStorage.getItem(TOKEN_KEY);
}

export function setToken(token: string): void {
    localStorage.setItem(TOKEN_KEY, token);
}

export function clearToken(): void {
    localStorage.removeItem(TOKEN_KEY);
}

export function isLoggedIn(): boolean {
    return getToken() !== null;
}

/**
 * Returns headers for an authenticated JSON request.
 * Includes Content-Type and, if a token is stored, Authorization: Bearer <token>.
 */
export function authHeaders(): Record<string, string> {
    const token = getToken();
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (token) {
        headers['Authorization'] = `Bearer ${token}`;
    }
    return headers;
}
