import { useState } from 'react';
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
  const [err, setErr] = useState('');
  const [msg, setMsg] = useState('');
  const [busy, setBusy] = useState(false);
  const clear = () => { setErr(''); setMsg(''); };

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
