import { useState } from 'react';
import api, { apiError } from '../api/client';
import { Alert, Field } from '../components/ui.jsx';

// Recover Applicant ID(s): Birth Cert + DOB -> OTP -> list of Applicant IDs.
// (Uses the same secure retrieve endpoints, but only reveals the IDs.)
export default function Recover() {
  const [bc, setBc] = useState('');
  const [dob, setDob] = useState('');
  const [sent, setSent] = useState(false);
  const [code, setCode] = useState('');
  const [ids, setIds] = useState(null);
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
      setIds(data.applications.map((a) => ({ id: a.application_id, cls: a.desired_class })));
    } catch (e) { setErr(apiError(e)); } finally { setBusy(false); }
  }

  return (
    <div className="card">
      <h2>Recover Applicant ID</h2>
      {err && <Alert kind="error">{err}</Alert>}
      {msg && <Alert kind="info">{msg}</Alert>}
      {!ids && (
        <>
          <div className="row">
            <Field label="Birth Certificate Number"><input value={bc} onChange={(e) => setBc(e.target.value)} placeholder="BC3001" /></Field>
            <Field label="Date of Birth"><input type="date" value={dob} onChange={(e) => setDob(e.target.value)} /></Field>
          </div>
          {!sent
            ? <button onClick={start} disabled={busy || !bc || !dob}>Send OTP</button>
            : (<><Field label="Enter OTP"><input value={code} onChange={(e) => setCode(e.target.value)} maxLength={6} /></Field>
              <button onClick={verify} disabled={busy || code.length !== 6}>Recover</button></>)}
        </>
      )}
      {ids && (
        ids.length
          ? <ul>{ids.map((x) => <li key={x.id}><b>{x.id}</b> — Class {x.cls}</li>)}</ul>
          : <p className="muted">No applications found.</p>
      )}
    </div>
  );
}
