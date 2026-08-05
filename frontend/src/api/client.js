import axios from 'axios';

// All requests go through /api (proxied to the Express backend in dev).
const api = axios.create({ baseURL: '/api' });

// Applicants are account-less, so there is no session to persist. The only
// credential is the short-lived (30 min) applicant token returned by
// /applications/retrieve, and it is deliberately kept in React component state
// — never in localStorage — so it disappears when the tab closes. The pages
// that need it attach it to that one request themselves.

// Normalize backend error messages to a thrown Error with a readable message.
export function apiError(e) {
  return e?.response?.data?.error || e?.response?.data?.details?.[0]?.message || e.message || 'Request failed';
}

export default api;
