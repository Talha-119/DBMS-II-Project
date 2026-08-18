import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import api, { apiError, logout } from '../api/client';
import { Alert, Field, Badge } from '../components/ui.jsx';

// Simple substring filter: keeps a row if `q` appears (case-insensitive) in
// any of the given fields. Empty query keeps everything.
function matchesQuery(row, fields, q) {
  const needle = q.trim().toLowerCase();
  if (!needle) return true;
  return fields.some((f) => String(row[f] ?? '').toLowerCase().includes(needle));
}

// Green / red state chip for the two switches that govern the public site.
function StatusLight({ on, onLabel, offLabel }) {
  return <span className={`status-light ${on ? 'on' : 'off'}`}>{on ? onLabel : offLabel}</span>;
}

export default function Admin() {
  const nav = useNavigate();
  const [schools, setSchools] = useState([]);
  const [dash, setDash] = useState(null);
  const [delReqs, setDelReqs] = useState([]);
  const [results, setResults] = useState([]);
  const [audit, setAudit] = useState([]);
  const [newSchool, setNewSchool] = useState({ name: '', postcode: '', school_gender: 'BOTH' });
  const [created, setCreated] = useState(null);
  const [quotas, setQuotas] = useState([]);
  const [nq, setNq] = useState({ code: '', name: '', priority: '', default_share: '', requires_reference: false, is_default: false });
  const [classes, setClasses] = useState([]);
  const [schoolClasses, setSchoolClasses] = useState([]);
  const [err, setErr] = useState('');
  const [msg, setMsg] = useState('');
  const [schoolSearch, setSchoolSearch] = useState('');
  const [resultSearch, setResultSearch] = useState('');
  const [auditSearch, setAuditSearch] = useState('');

  async function loadAll() {
    setErr('');
    // Each panel (dashboard, schools, results, ...) is loaded independently:
    // one failing endpoint (e.g. quota-types) must not blank out the others, since
    // create/delete school, view schools, run lottery and see results are the
    // core master-admin features and must keep working even if a side panel errors.
    const specs = [
      ['/admin/dashboard', setDash],
      ['/admin/schools', setSchools],
      ['/admin/deletion-requests', setDelReqs],
      ['/admin/results', setResults],
      ['/admin/audit', setAudit],
      ['/admin/quota-types', setQuotas],
      ['/admin/class-eligibility', setClasses],
      ['/admin/school-class-eligibility', setSchoolClasses],
    ];
    const outcomes = await Promise.allSettled(specs.map(([url]) => api.get(url)));
    const failures = [];
    outcomes.forEach((outcome, i) => {
      const [url, setter] = specs[i];
      if (outcome.status === 'fulfilled') setter(outcome.value.data);
      else failures.push(`${url}: ${apiError(outcome.reason)}`);
    });
    if (failures.length) setErr(failures.join(' | '));
  }

  async function addQuota(e) {
    e.preventDefault(); setErr(''); setMsg('');
    try {
      await api.post('/admin/quota-types', {
        code: nq.code.trim().toUpperCase(), name: nq.name, priority: Number(nq.priority),
        default_share: Number(nq.default_share), requires_reference: nq.requires_reference, is_default: nq.is_default,
      });
      setMsg(`Quota ${nq.code.toUpperCase()} saved. Click "Rebalance seats" to apply % to existing seats.`);
      setNq({ code: '', name: '', priority: '', default_share: '', requires_reference: false, is_default: false });
      loadAll();
    } catch (e) { setErr(apiError(e)); }
  }
  async function rebalance() {
    setErr(''); setMsg('');
    try { await api.post('/admin/quota-types/rebalance'); setMsg('All seats rebalanced to current quota %.'); loadAll(); }
    catch (e) { setErr(apiError(e)); }
  }
  // Local date parts, not toISOString(): the API sends dates as UTC instants, so
  // toISOString() would shift them a day back when displayed here.
  const isoDate = (d) => {
    const x = new Date(d);
    return `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, '0')}-${String(x.getDate()).padStart(2, '0')}`;
  };

  async function delQuota(code) {
    if (!window.confirm(`Delete quota ${code}? (Blocked if any seat/choice uses it.)`)) return;
    try { await api.delete(`/admin/quota-types/${code}`); loadAll(); } catch (e) { setErr(apiError(e)); }
  }
  useEffect(() => { loadAll(); }, []);

  async function addSchool(e) {
    e.preventDefault(); setErr(''); setMsg(''); setCreated(null);
    try {
      const { data } = await api.post('/admin/schools', newSchool);
      setCreated(data);
      setNewSchool({ name: '', postcode: '', school_gender: 'BOTH' });
      loadAll();
    } catch (e) { setErr(apiError(e)); }
  }

  // Two separate decisions, two separate buttons. Running the draw allocates
  // seats and closes the window; nobody outside this page can see the outcome
  // until "Publish results" is pressed.
  async function runLottery() {
    setErr(''); setMsg('');
    const round = (dash?.current_round || 0) + 1;
    const warning = dash?.result_ready
      ? `\n\nThe currently published result will be UNPUBLISHED, because re-running changes it.`
      : '';
    if (!window.confirm(
      `Run the admission lottery (round ${round}) now?\n\n`
      + 'This closes the application window and allocates seats. '
      + 'Results are NOT published — applicants will not see them until you press "Publish results".'
      + warning)) return;
    try {
      await api.post('/admin/lottery', { round });
      setMsg(`Lottery round ${round} completed. Results are saved but NOT published — review them below, then press "Publish results".`);
      loadAll();
    } catch (e) { setErr(apiError(e)); }
  }

  async function publishResults() {
    setErr(''); setMsg('');
    if (!window.confirm('Publish the results?\n\nEvery applicant will immediately be able to look up their result from the landing page.')) return;
    try { await api.post('/admin/results/publish'); setMsg('Results published — "Check Result" is now open to applicants.'); loadAll(); }
    catch (e) { setErr(apiError(e)); }
  }

  async function unpublishResults() {
    setErr(''); setMsg('');
    if (!window.confirm('Unpublish the results?\n\n"Check Result" becomes inaccessible again. Applicants who already saw their result will remember it.')) return;
    try { await api.post('/admin/results/unpublish'); setMsg('Results unpublished — the public result lookup is closed.'); loadAll(); }
    catch (e) { setErr(apiError(e)); }
  }

  async function decide(id, approve) {
    setErr(''); setMsg('');
    try { await api.post(`/admin/deletion-requests/${id}`, { approve }); setMsg(`Request ${approve ? 'approved' : 'rejected'}.`); loadAll(); }
    catch (e) { setErr(apiError(e)); }
  }

  // The button always states the action it performs ("Close applications"),
  // never the state it is in — the chip beside it carries the state.
  async function setRoundOpen(open) {
    setErr(''); setMsg('');
    if (!window.confirm(open
      ? 'Open applications? Applicants will be able to submit new forms again.'
      : 'Close applications? No new form can be submitted until you re-open.')) return;
    try {
      await api.post('/admin/round', { open });
      setMsg(open ? 'Applications are now OPEN.' : 'Applications are now CLOSED.');
      loadAll();
    } catch (e) { setErr(apiError(e)); }
  }

  async function deleteSchool(eiin) {
    if (!window.confirm(`Delete school ${eiin} and its seats?`)) return;
    try { await api.delete(`/admin/schools/${eiin}`); loadAll(); } catch (e) { setErr(apiError(e)); }
  }

  function signOut() { logout(); nav('/login'); }

  const filteredSchools = useMemo(
    () => schools.filter((s) => matchesQuery(s, ['eiin', 'name', 'postcode'], schoolSearch)),
    [schools, schoolSearch],
  );
  const filteredResults = useMemo(
    () => results.filter((r) => matchesQuery(
      r, ['application_id', 'student_name', 'status', 'allocated_quota', 'school_name', 'class_level'], resultSearch,
    )),
    [results, resultSearch],
  );
  const filteredAudit = useMemo(
    () => audit.filter((a) => matchesQuery(a, ['log_id', 'table_name', 'action'], auditSearch)),
    [audit, auditSearch],
  );

  return (
    <>
      <div className="card">
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <h2>Master Admin</h2>
          <button className="btn-secondary" onClick={signOut}>Logout</button>
        </div>
        {err && <Alert kind="error">{err}</Alert>}
        {msg && <Alert kind="ok">{msg}</Alert>}

        {/* Rendered only once the real state is known — a red "Closed" light
            flashing during the first load would be a lie about the live site. */}
        {!dash ? <p className="muted">Loading status…</p> : (
        <div className="ops-grid">
          {/* Switch 1 — the application window. */}
          <div className="ops-panel">
            <div className="ops-head">
              <span className="ops-title">Applications</span>
              <StatusLight on={!!dash?.round_open} onLabel="Open" offLabel="Closed" />
            </div>
            <p className="help">
              {dash?.round_open
                ? 'Applicants can submit new forms right now.'
                : 'No new form can be submitted. Running the lottery closes this automatically.'}
            </p>
            {dash?.round_open
              ? <button className="btn-danger" onClick={() => setRoundOpen(false)}>Close applications</button>
              : <button className="btn-ready" onClick={() => setRoundOpen(true)}>Open applications</button>}
          </div>

          {/* Switch 2 — publication, deliberately independent of the draw. */}
          <div className="ops-panel">
            <div className="ops-head">
              <span className="ops-title">Results</span>
              <StatusLight on={!!dash?.result_ready} onLabel="Published" offLabel="Not published" />
            </div>
            <p className="help">
              {dash?.result_ready
                ? 'Applicants can look up their result from the landing page.'
                : dash?.results_pending_publish
                  ? `Round ${dash.current_round} is allocated but hidden from applicants — review the results below, then publish.`
                  : 'Nothing to publish yet. Run the lottery first.'}
            </p>
            <div className="btn-row" style={{ marginTop: 0 }}>
              <button className="btn-secondary" onClick={runLottery}>
                ▶ Run lottery{dash?.current_round ? ` (round ${dash.current_round + 1})` : ''}
              </button>
              {dash?.result_ready
                ? <button className="btn-danger" onClick={unpublishResults}>Unpublish results</button>
                : (
                  <button
                    className="btn-ready"
                    onClick={publishResults}
                    disabled={!dash?.results_pending_publish}
                    title={dash?.results_pending_publish ? '' : 'Run the lottery first'}
                  >
                    Publish results
                  </button>
                )}
            </div>
          </div>
        </div>
        )}

        {dash && (
          <div className="ops-stats">
            <div><b>{dash.counts.applications}</b><span>Applications</span></div>
            <div><b>{dash.counts.admitted}</b><span>Admitted</span></div>
            <div><b>{dash.counts.waiting}</b><span>Waiting</span></div>
            <div>
              <b>{dash.current_round || '—'}</b>
              <span>{dash.last_run_at ? `Last run ${new Date(dash.last_run_at).toLocaleString()}` : 'Rounds run'}</span>
            </div>
          </div>
        )}
      </div>

      <div className="card">
        <h3>Create school</h3>
        <form onSubmit={addSchool} className="row">
          <Field label="Name"><input value={newSchool.name} onChange={(e) => setNewSchool({ ...newSchool, name: e.target.value })} /></Field>
          <Field label="Postcode"><input value={newSchool.postcode} onChange={(e) => setNewSchool({ ...newSchool, postcode: e.target.value })} placeholder="1000" /></Field>
          <Field label="Gender"><select value={newSchool.school_gender} onChange={(e) => setNewSchool({ ...newSchool, school_gender: e.target.value })}><option>BOTH</option><option>MALE</option><option>FEMALE</option></select></Field>
          <div style={{ alignSelf: 'end' }}><button type="submit">Create</button></div>
        </form>
        {created && <Alert kind="ok">Created EIIN <b>{created.eiin}</b> — temporary password <b>{created.temp_password}</b> (shown once).</Alert>}
        <Field label="Search schools">
          <input
            value={schoolSearch}
            onChange={(e) => setSchoolSearch(e.target.value)}
            placeholder="Search by EIIN, name, or postcode…"
          />
        </Field>
        <table style={{ marginTop: 12 }}>
          <thead><tr><th>EIIN</th><th>Name</th><th>Postcode</th><th>Seats left</th><th>Admitted</th><th></th></tr></thead>
          <tbody>
            {filteredSchools.length === 0 && (
              <tr><td colSpan={6} className="muted">No schools match "{schoolSearch}".</td></tr>
            )}
            {filteredSchools.map((s) => (
              <tr key={s.eiin}><td>{s.eiin}</td><td>{s.name}</td><td>{s.postcode}</td><td>{s.seats_remaining}</td><td>{s.admitted_count}</td>
                <td><button className="btn-danger" onClick={() => deleteSchool(s.eiin)}>Delete</button></td></tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="card">
        <h3>Quota types (extensible)</h3>
        <p className="help">Add a quota, retune its % (default share) or priority, or move the catch-all. After changing %, click <b>Rebalance seats</b> to apply to existing seats (only before the lottery). Priority 1 is allocated first.</p>
        <table>
          <thead><tr><th>Code</th><th>Name</th><th>Priority</th><th>Share</th><th>Needs Ref</th><th>Catch-all</th><th></th></tr></thead>
          <tbody>
            {quotas.map((q) => (
              <tr key={q.code}>
                <td>{q.code}</td><td>{q.name}</td><td>{q.priority}</td>
                <td>{(Number(q.default_share) * 100).toFixed(1)}%</td>
                <td>{q.requires_reference ? 'yes' : 'no'}</td><td>{q.is_default ? '✓' : ''}</td>
                <td><button className="btn-danger" onClick={() => delQuota(q.code)}>Delete</button></td>
              </tr>
            ))}
          </tbody>
        </table>
        <form onSubmit={addQuota} className="row" style={{ marginTop: 12 }}>
          <Field label="Code"><input value={nq.code} onChange={(e) => setNq({ ...nq, code: e.target.value })} placeholder="SIBLING" /></Field>
          <Field label="Name"><input value={nq.name} onChange={(e) => setNq({ ...nq, name: e.target.value })} placeholder="Sibling Quota" /></Field>
          <Field label="Priority"><input type="number" min="1" value={nq.priority} onChange={(e) => setNq({ ...nq, priority: e.target.value })} /></Field>
          <Field label="Share (0-1)"><input type="number" step="0.01" min="0" max="1" value={nq.default_share} onChange={(e) => setNq({ ...nq, default_share: e.target.value })} placeholder="0.05" /></Field>
          <Field label="Needs ref"><select value={nq.requires_reference ? 'y' : 'n'} onChange={(e) => setNq({ ...nq, requires_reference: e.target.value === 'y' })}><option value="n">No</option><option value="y">Yes</option></select></Field>
          <div style={{ alignSelf: 'end' }} className="btn-row">
            <button type="submit">Save quota</button>
            <button type="button" className="btn-secondary" onClick={rebalance}>Rebalance seats</button>
          </div>
        </form>
      </div>

      <div className="card">
        <h3>Class age eligibility — national baseline (read-only)</h3>
        <p className="help">
          The nationally accepted date-of-birth window for each class, and the outer bound every
          school must stay inside. Admission criteria are set by each school, so this is not editable
          here — a school authority narrows its own window from its portal. Age limits are shown at
          1 January of the admission year.
        </p>
        <table>
          <thead><tr><th>Class</th><th>Accepted from</th><th>Accepted to</th><th>Age limit</th></tr></thead>
          <tbody>
            {classes.map((c) => (
              <tr key={c.class_level}>
                <td>Class {c.class_level}</td>
                <td>{isoDate(c.min_dob)}</td>
                <td>{isoDate(c.max_dob)}</td>
                <td>{c.min_age}-{c.max_age}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="card">
        <h3>Schools with their own criteria ({schoolClasses.length})</h3>
        <p className="help">Schools that have narrowed a class window below the national baseline.</p>
        {schoolClasses.length === 0
          ? <p className="muted">None — every school currently uses the national windows.</p>
          : (
            <table>
              <thead><tr><th>EIIN</th><th>School</th><th>Class</th><th>Accepts from</th><th>Accepts to</th><th>National</th></tr></thead>
              <tbody>
                {schoolClasses.map((s) => (
                  <tr key={`${s.eiin}-${s.class_level}`}>
                    <td>{s.eiin}</td><td>{s.school_name}</td><td>Class {s.class_level}</td>
                    <td>{isoDate(s.min_dob)}</td><td>{isoDate(s.max_dob)}</td>
                    <td className="muted">{isoDate(s.national_min_dob)} … {isoDate(s.national_max_dob)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
      </div>

      <div className="card">
        <h3>Pending deletion requests ({delReqs.length})</h3>
        {delReqs.length === 0 && <p className="muted">None.</p>}
        {delReqs.length > 0 && (
          <table>
            <thead><tr><th>Request</th><th>Application</th><th>Student</th><th>Reason</th><th></th></tr></thead>
            <tbody>
              {delReqs.map((d) => (
                <tr key={d.request_id}>
                  <td>{d.request_id}</td><td>{d.application_id}</td><td>{d.student_name}</td><td>{d.reason || '—'}</td>
                  <td className="btn-row">
                    <button onClick={() => decide(d.request_id, true)}>Approve</button>
                    <button className="btn-secondary" onClick={() => decide(d.request_id, false)}>Reject</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div className="card">
        <h3>Results ({results.length})</h3>
        {results.length > 0 && (dash?.result_ready
          ? <p className="help">Published — applicants can look these up from the landing page.</p>
          : <Alert kind="warn">Draft — visible to you only. Applicants cannot look these up until you press <b>Publish results</b>.</Alert>
        )}
        <Field label="Search results">
          <input
            value={resultSearch}
            onChange={(e) => setResultSearch(e.target.value)}
            placeholder="Search by applicant, student, status, quota, school, or class…"
          />
        </Field>
        <table>
          <thead><tr><th>Applicant</th><th>Student</th><th>Status</th><th>Quota</th><th>School</th><th>Class</th></tr></thead>
          <tbody>
            {filteredResults.length === 0 && (
              <tr><td colSpan={6} className="muted">No results match "{resultSearch}".</td></tr>
            )}
            {filteredResults.map((r) => (
              <tr key={r.application_id}><td>{r.application_id}</td><td>{r.student_name}</td><td><Badge value={r.status} /></td><td>{r.allocated_quota || '—'}</td><td>{r.school_name || '—'}</td><td>{r.class_level || '—'}</td></tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="card">
        <h3>Recent audit log (triggers)</h3>
        <Field label="Search audit log">
          <input
            value={auditSearch}
            onChange={(e) => setAuditSearch(e.target.value)}
            placeholder="Search by table or action…"
          />
        </Field>
        <table>
          <thead><tr><th>#</th><th>Table</th><th>Action</th><th>At</th></tr></thead>
          <tbody>
            {filteredAudit.length === 0 && (
              <tr><td colSpan={4} className="muted">No audit entries match "{auditSearch}".</td></tr>
            )}
            {filteredAudit.map((a) => (
              <tr key={a.log_id}><td>{a.log_id}</td><td>{a.table_name}</td><td>{a.action}</td><td>{new Date(a.at).toLocaleString()}</td></tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
