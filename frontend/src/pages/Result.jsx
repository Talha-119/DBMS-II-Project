import { useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import api, { apiError } from '../api/client';
import { Alert, Field, Badge } from '../components/ui.jsx';

// Which list an applicant landed on, like the portal's merit / 1st / 2nd
// waiting lists. Round 1 admits = merit list; later rounds = waiting-list calls.
function tierLabel(r) {
  if (r.status === 'ADMITTED') return r.round > 1 ? `Waiting list ${r.round - 1} (round ${r.round})` : 'Merit list';
  if (r.status === 'WAITING') return `Waiting list ${r.round || 1}`;
  return '—';
}

export default function Result() {
  const [params] = useSearchParams();
  const [bc, setBc] = useState('');
  const [track, setTrack] = useState(params.get('type') || '');
  const [rows, setRows] = useState(null);
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);

  async function check() {
    setErr(''); setRows(null); setBusy(true);
    try {
      const { data } = await api.get(`/results/${encodeURIComponent(bc.trim())}`,
        { params: track ? { type: track } : {} });
      setRows(data);
    } catch (e) { setErr(apiError(e)); } finally { setBusy(false); }
  }

  return (
    <div className="card">
      <h2>Check Result{track && ` — ${track === 'GOVERNMENT' ? 'Government' : 'Non-Government'} schools`}</h2>
      {err && <Alert kind="error">{err}</Alert>}
      <div className="row">
        <Field label="Birth Certificate Number"><input value={bc} onChange={(e) => setBc(e.target.value)} placeholder="BC3001" /></Field>
        <Field label="School track">
          <select value={track} onChange={(e) => setTrack(e.target.value)}>
            <option value="">All schools</option>
            <option value="GOVERNMENT">Government</option>
            <option value="NON_GOVERNMENT">Non-Government</option>
          </select>
        </Field>
        <div style={{ alignSelf: 'end' }}><button onClick={check} disabled={busy || !bc}>Check</button></div>
      </div>

      {rows && rows.length === 0 && <p className="muted" style={{ marginTop: 14 }}>No result found for this birth certificate.</p>}
      {rows && rows.length > 0 && (
        <table style={{ marginTop: 14 }}>
          <thead><tr><th>Applicant ID</th><th>List</th><th>Status</th><th>Quota</th><th>School</th><th>Track</th><th>Class</th><th>Shift</th></tr></thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.application_id}>
                <td>{r.application_id}</td>
                <td>{tierLabel(r)}</td>
                <td><Badge value={r.status} /></td>
                <td>{r.allocated_quota || '—'}</td>
                <td>{r.school_name || '—'}</td>
                <td>{r.school_type ? (r.school_type === 'GOVERNMENT' ? 'Govt' : 'Non-Govt') : '—'}</td>
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
