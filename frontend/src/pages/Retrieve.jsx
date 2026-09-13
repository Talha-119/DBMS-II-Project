import { useState, useEffect } from 'react';
import axios from 'axios';
import api, { apiError } from '../api/client';
import { Alert, Field, Badge } from '../components/ui.jsx';

// Applicant retrieval: Birth Cert + DOB -> OTP -> view applications, download PDF,
// or request deletion. Uses a short-lived applicant token (kept in component state).
export default function Retrieve() {
  const [bc, setBc] = useState('');
  const [dob, setDob] = useState('');
  const [sent, setSent] = useState(false);
  const [code, setCode] = useState('');
  const [token, setToken] = useState('');
  const [apps, setApps] = useState(null);
  const [notifs, setNotifs] = useState([]);
  const [err, setErr] = useState('');
  const [msg, setMsg] = useState('');
  const [busy, setBusy] = useState(false);
  const [photo, setPhoto] = useState('');
  const clear = () => { setErr(''); setMsg(''); };

  // Release the object URL when this page goes away, so the blob is not pinned
  // in memory for the lifetime of the tab.
  useEffect(() => () => { if (photo) URL.revokeObjectURL(photo); }, [photo]);

  // The photograph comes back out of Postgres on every load of this page -- it
  // is not carried over from the apply form and is not in any cache, which is
  // the point: it demonstrates that the bytes really are in the database. The
  // endpoint is token-gated, so it is fetched as a blob rather than pointed at
  // by an <img src>, which could not carry the Authorization header.
  async function loadPhoto(tok) {
    try {
      const res = await axios.get(`/api/applications/student/${encodeURIComponent(bc.trim())}/photo`, {
        responseType: 'blob', headers: { Authorization: `Bearer ${tok}` },
      });
      setPhoto(URL.createObjectURL(res.data));
    } catch { /* 404 = this applicant never uploaded one; the box stays empty */ }
  }

  async function loadNotifications(tok) {
    try {
      const res = await axios.get('/api/applications/notifications', { headers: { Authorization: `Bearer ${tok}` } });
      setNotifs(res.data);
    } catch { /* non-critical: the applications table above still loads fine without it */ }
  }

  async function markNotifRead(id) {
    setNotifs((prev) => prev.map((n) => (n.notification_id === id ? { ...n, is_read: true } : n)));
    try { await axios.post(`/api/applications/notifications/${id}/read`, {}, { headers: { Authorization: `Bearer ${token}` } }); } catch { /* best-effort */ }
  }

  async function markAllNotifsRead() {
    setNotifs((prev) => prev.map((n) => ({ ...n, is_read: true })));
    try { await axios.post('/api/applications/notifications/read-all', {}, { headers: { Authorization: `Bearer ${token}` } }); } catch { /* best-effort */ }
  }

  async function start() {
    clear(); setBusy(true);
    try {
      const { data } = await api.post('/applications/retrieve/start', { bc_no: bc.trim(), dob });
      setSent(true);
      setMsg(`OTP sent to ${data.mobile_masked}.` + (data.dev_code ? ` [DEMO code: ${data.dev_code}]` : ''));
    } catch (e) { setErr(apiError(e)); } finally { setBusy(false); }
  }

  async function verify() {
    clear(); setBusy(true);
    try {
      const { data } = await api.post('/applications/retrieve', { bc_no: bc.trim(), dob, code: code.trim() });
      setToken(data.token); setApps(data.applications);
      loadNotifications(data.token);
      loadPhoto(data.token);
    } catch (e) { setErr(apiError(e)); } finally { setBusy(false); }
  }

  async function downloadPdf(id) {
    clear();
    try {
      const res = await axios.get(`/api/applications/${id}/pdf`, {
        responseType: 'blob', headers: { Authorization: `Bearer ${token}` },
      });
      const url = URL.createObjectURL(res.data);
      const a = document.createElement('a');
      a.href = url; a.download = `${id}.pdf`; a.click();
      URL.revokeObjectURL(url);
    } catch (e) { setErr('Download failed: ' + apiError(e)); }
  }

  async function payFee(id) {
    clear();
    try {
      await axios.post(`/api/applications/${id}/pay`, { method: 'CARD' }, { headers: { Authorization: `Bearer ${token}` } });
      setMsg('Fee paid successfully.');
      setApps((prev) => prev.map((a) => (a.application_id === id ? { ...a, payment_status: 'PAID' } : a)));
      loadNotifications(token);
    } catch (e) { setErr('Payment failed: ' + apiError(e)); }
  }

  async function requestDelete(id) {
    clear();
    try {
      const otp = await axios.post(`/api/applications/${id}/delete-otp`, {}, { headers: { Authorization: `Bearer ${token}` } });
      const entered = window.prompt(`Enter the deletion OTP${otp.data.dev_code ? ' (DEMO: ' + otp.data.dev_code + ')' : ''}:`);
      if (!entered) return;
      const reason = window.prompt('Reason for deletion (optional):') || '';
      await axios.post(`/api/applications/${id}/delete-request`, { otp_code: entered.trim(), reason },
        { headers: { Authorization: `Bearer ${token}` } });
      setMsg('Deletion request submitted. A master admin will review it.');
    } catch (e) { setErr(apiError(e)); }
  }

  return (
    <div className="card">
      <h2>Download / Delete Application</h2>
      {err && <Alert kind="error">{err}</Alert>}
      {msg && <Alert kind="info">{msg}</Alert>}

      {!apps && (
        <>
          <div className="row">
            <Field label="Birth Certificate Number"><input value={bc} onChange={(e) => setBc(e.target.value)} placeholder="BC3001" /></Field>
            <Field label="Date of Birth"><input type="date" value={dob} onChange={(e) => setDob(e.target.value)} /></Field>
          </div>
          {!sent
            ? <button onClick={start} disabled={busy || !bc || !dob}>Send OTP</button>
            : (
              <>
                <Field label="Enter OTP"><input value={code} onChange={(e) => setCode(e.target.value)} maxLength={6} placeholder="######" /></Field>
                <button onClick={verify} disabled={busy || code.length !== 6}>Verify</button>
              </>
            )}
        </>
      )}

      {apps && (
        <>
          {notifs.length > 0 && (
            <div className="card notif-inline">
              <div className="notif-inline-head">
                <h3>Announcements</h3>
                {notifs.some((n) => !n.is_read) && (
                  <button className="btn-secondary" onClick={markAllNotifsRead}>Mark all read</button>
                )}
              </div>
              <ul className="notif-list">
                {notifs.map((n) => (
                  <li
                    key={n.notification_id}
                    className={n.is_read ? '' : 'unread'}
                    onClick={() => !n.is_read && markNotifRead(n.notification_id)}
                  >
                    <div className="notif-title">{n.title}</div>
                    {n.body && <div className="notif-body">{n.body}</div>}
                    <div className="notif-time">{new Date(n.created_at).toLocaleString()}</div>
                  </li>
                ))}
              </ul>
            </div>
          )}
          <div className="retrieve-photo">
            <div className={`photo-slot${photo ? '' : ' empty'}`}>
              {photo ? <img src={photo} alt="Applicant photograph" /> : <span>No photograph</span>}
            </div>
            <div className="retrieve-photo-note">
              {photo
                ? <>Photograph on file for <b>{bc.trim()}</b>, served from the database. It is part of your locked profile and prints on your applicant copy.</>
                : <>No photograph is on file for <b>{bc.trim()}</b>. You can attach one to your next application.</>}
            </div>
          </div>

          {apps.length === 0 && <p className="muted">No applications found.</p>}
          {apps.length > 0 && (
            <table>
              <thead><tr><th>Applicant ID</th><th>Class</th><th>Area</th><th>Status</th><th>Fee</th><th>Submitted</th><th></th></tr></thead>
              <tbody>
                {apps.map((a) => (
                  <tr key={a.application_id}>
                    <td>{a.application_id}</td>
                    <td>{a.desired_class}</td>
                    <td>{a.thana}, {a.district}</td>
                    <td><Badge value={a.status} /></td>
                    <td>{a.payment_status === 'PAID' ? <span className="badge ADMITTED">PAID</span> : <span className="badge WAITING">PENDING</span>}</td>
                    <td>{new Date(a.submitted_at).toLocaleDateString()}</td>
                    <td className="btn-row">
                      <button className="btn-secondary" onClick={() => downloadPdf(a.application_id)}>PDF</button>
                      {a.payment_status !== 'PAID' && <button onClick={() => payFee(a.application_id)}>Pay {a.fee_amount || ''}</button>}
                      <button className="btn-danger" onClick={() => requestDelete(a.application_id)}>Delete</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </>
      )}
    </div>
  );
}
