import { useState } from 'react';
import api, { apiError } from '../../api/client';
import { Alert, Badge } from '../ui.jsx';

const STATUS_OPTIONS = ['ALL', 'ADMITTED', 'NOT_ADMITTED', 'WAITLISTED'];

export default function LotteryResultsViewer() {
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState('ALL');
  const [results, setResults] = useState([]);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState('');
  const [msg, setMsg] = useState('');
  const [searched, setSearched] = useState(false);

  async function fetchResults(e) {
    e && e.preventDefault();
    setErr(''); setMsg(''); setLoading(true); setSearched(true);
    try {
      const params = new URLSearchParams();
      if (search.trim()) params.set('search', search.trim());
      if (status !== 'ALL') params.set('status', status);
      const { data } = await api.get(`/admin/lottery-results?${params}`);
      setResults(data);
    } catch (e) {
      setErr(apiError(e));
    } finally {
      setLoading(false);
    }
  }

  async function disqualify(applicationId) {
    const reason = window.prompt(`Enter disqualification reason for ${applicationId}:`);
    if (!reason) return;
    setErr(''); setMsg('');
    try {
      await api.post('/admin/lottery/disqualify', { applicationId, reason });
      setMsg(`Application ${applicationId} disqualified.`);
      fetchResults();
    } catch (e) {
      setErr(apiError(e));
    }
  }

  return (
    <>
      <h3>Lottery Results Viewer</h3>
      {err && <Alert kind="error">{err}</Alert>}
      {msg && <Alert kind="ok">{msg}</Alert>}

      <form onSubmit={fetchResults} className="row" style={{ marginBottom: 12, gap: 8, flexWrap: 'wrap' }}>
        <input
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          placeholder="Search by application ID, name, or BC no."
          style={{ flex: 1, minWidth: 200 }}
        />
        <select value={status} onChange={(e) => setStatus(e.target.value)}>
          {STATUS_OPTIONS.map((s) => (
            <option key={s} value={s}>{s}</option>
          ))}
        </select>
        <button type="submit" disabled={loading}>
          {loading ? 'Searching…' : 'Search'}
        </button>
      </form>

      {searched && results.length === 0 && !loading && (
        <p className="muted">No results found.</p>
      )}

      {results.length > 0 && (
        <table>
          <thead>
            <tr>
              <th>Application</th>
              <th>Student</th>
              <th>Result</th>
              <th>Lifecycle</th>
              <th>School</th>
              <th>Class</th>
              <th>Quota</th>
              <th>Round</th>
              <th>Decided</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {results.map((r) => (
              <tr key={r.application_id}>
                <td>{r.application_id}</td>
                <td>{r.student_name}</td>
                <td><Badge value={r.status} /></td>
                <td>
                  {r.lifecycle_status
                    ? <Badge value={r.lifecycle_status} />
                    : <span className="muted">—</span>}
                </td>
                <td>{r.school_name || '—'}</td>
                <td>{r.class_level || '—'}</td>
                <td>{r.allocated_quota || '—'}</td>
                <td>{r.round}</td>
                <td>{r.decided_at ? new Date(r.decided_at).toLocaleDateString() : '—'}</td>
                <td>
                  {r.lifecycle_status !== 'DISQUALIFIED' && r.lifecycle_status !== 'FORFEITED' && (
                    <button
                      className="btn-danger"
                      style={{ fontSize: '0.8rem', padding: '2px 8px' }}
                      onClick={() => disqualify(r.application_id)}
                    >
                      Disqualify
                    </button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </>
  );
}
