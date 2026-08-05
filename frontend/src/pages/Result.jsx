import { useState } from 'react';
import api, { apiError } from '../api/client';
import { Alert, Field, Badge } from '../components/ui.jsx';

export default function Result() {
  const [bc, setBc] = useState('');
  const [rows, setRows] = useState(null);
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);

  async function check() {
    setErr(''); setRows(null); setBusy(true);
    try {
      const { data } = await api.get(`/results/${encodeURIComponent(bc.trim())}`);
      setRows(data);
    } catch (e) { setErr(apiError(e)); } finally { setBusy(false); }
  }

  return (
    <div className="card">
      <h2>Check Result</h2>
      {err && <Alert kind="error">{err}</Alert>}
      <Field label="Birth Certificate Number"><input value={bc} onChange={(e) => setBc(e.target.value)} placeholder="BC3001" /></Field>
      <button onClick={check} disabled={busy || !bc}>Check</button>

      {rows && rows.length === 0 && <p className="muted" style={{ marginTop: 14 }}>No result found for this birth certificate.</p>}
      {rows && rows.length > 0 && (
        <table style={{ marginTop: 14 }}>
          <thead><tr><th>Applicant ID</th><th>Status</th><th>Quota</th><th>School</th><th>Class</th><th>Shift</th></tr></thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.application_id}>
                <td>{r.application_id}</td>
                <td><Badge value={r.status} /></td>
                <td>{r.allocated_quota || '—'}</td>
                <td>{r.school_name || '—'}</td>
                <td>{r.class_level || '—'}</td>
                <td>{r.shift || '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
