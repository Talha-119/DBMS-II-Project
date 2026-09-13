import { useEffect, useRef, useState } from 'react';
import api, { apiError } from '../api/client';

// Megaphone, drawn inline rather than pulled from an icon package or a CDN:
// no extra dependency, no network request, and it inherits the header's colour
// through `currentColor` so it themes itself. A megaphone rather than a bell
// because what lands here is an announcement, not an alarm.
//
// Geometry is the MIT-licensed Lucide "megaphone" outline.
function MegaphoneIcon() {
  return (
    <svg
      className="announce-icon"
      viewBox="0 0 24 24"
      width="18"
      height="18"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      <path d="m3 11 18-5v12L3 14v-3z" />
      <path d="M11.6 16.8a3 3 0 1 1-5.8-1.6" />
    </svg>
  );
}

// Polls a staff announcement inbox (authority or admin — same response shape,
// see backend/src/routes/{authority,admin}.js) and renders the megaphone with an
// unread badge + dropdown. The bearer token already scopes the list
// server-side (by EIIN for a school, or the shared admin inbox), so this
// component only needs to know which base path to hit.
//
// The API path stays /notifications: renaming the route and the table would
// mean a migration and a backend change for a wording choice, so the rename is
// kept to what people actually read.
export default function AnnouncementBell({ basePath }) {
  const [items, setItems] = useState([]);
  const [open, setOpen] = useState(false);
  const [err, setErr] = useState('');
  const boxRef = useRef(null);

  async function load() {
    try {
      const { data } = await api.get(`${basePath}/notifications`);
      setItems(data);
      setErr('');
    } catch (e) { setErr(apiError(e)); }
  }

  useEffect(() => {
    load();
    const id = setInterval(load, 30000); // light polling — no websocket layer here
    return () => clearInterval(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [basePath]);

  useEffect(() => {
    function onClick(e) {
      if (boxRef.current && !boxRef.current.contains(e.target)) setOpen(false);
    }
    document.addEventListener('mousedown', onClick);
    return () => document.removeEventListener('mousedown', onClick);
  }, []);

  const unread = items.filter((n) => !n.is_read).length;

  async function markRead(id) {
    setItems((prev) => prev.map((n) => (n.notification_id === id ? { ...n, is_read: true } : n)));
    try { await api.post(`${basePath}/notifications/${id}/read`); } catch { /* best-effort */ }
  }

  async function markAll() {
    setItems((prev) => prev.map((n) => ({ ...n, is_read: true })));
    try { await api.post(`${basePath}/notifications/read-all`); } catch { /* best-effort */ }
  }

  return (
    <div className="notif" ref={boxRef}>
      <button
        className="notif-bell"
        onClick={() => setOpen((o) => !o)}
        aria-label={unread > 0 ? `Announcements (${unread} unread)` : 'Announcements'}
        title="Announcements"
        type="button"
      >
        <MegaphoneIcon />
        {unread > 0 && <span className="notif-count">{unread > 9 ? '9+' : unread}</span>}
      </button>
      {open && (
        <div className="notif-panel">
          <div className="notif-head">
            <b>Announcements</b>
            {unread > 0 && <button className="btn-secondary notif-markall" onClick={markAll} type="button">Mark all read</button>}
          </div>
          {err && <div className="notif-empty">{err}</div>}
          {!err && items.length === 0 && <div className="notif-empty">No announcements yet.</div>}
          {!err && items.length > 0 && (
            <ul className="notif-list">
              {items.map((n) => (
                <li
                  key={n.notification_id}
                  className={n.is_read ? '' : 'unread'}
                  onClick={() => !n.is_read && markRead(n.notification_id)}
                >
                  <div className="notif-title">{n.title}</div>
                  {n.body && <div className="notif-body">{n.body}</div>}
                  <div className="notif-time">{new Date(n.created_at).toLocaleString()}</div>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </div>
  );
}
