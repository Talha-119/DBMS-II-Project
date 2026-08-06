import axios from 'axios';

// All requests go through /api (proxied to the Express backend in dev).
const api = axios.create({ baseURL: '/api' });

// --- token storage (privileged sessions) ---
const TOKEN_KEY = 'gsa_token';
export function setToken(t) {
  if (t) localStorage.setItem(TOKEN_KEY, t);
  else localStorage.removeItem(TOKEN_KEY);
}
export function getToken() {
  return localStorage.getItem(TOKEN_KEY);
}

api.interceptors.request.use((config) => {
  const t = getToken();
  if (t) config.headers.Authorization = `Bearer ${t}`;
  return config;
});

// --- role storage (to route staff to the right portal) ---
const ROLE_KEY = 'gsa_role';
export function setRole(r) {
  if (r) localStorage.setItem(ROLE_KEY, r);
  else localStorage.removeItem(ROLE_KEY);
}
export function getRole() {
  return localStorage.getItem(ROLE_KEY);
}
export function logout() {
  setToken(null);
  setRole(null);
}

// Normalize backend error messages to a thrown Error with a readable message.
export function apiError(e) {
  return e?.response?.data?.error || e?.response?.data?.details?.[0]?.message || e.message || 'Request failed';
}

export default api;
