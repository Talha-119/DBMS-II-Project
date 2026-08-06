import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import api, { apiError, logout } from '../api/client';
import { Alert, Field, Badge } from '../components/ui.jsx';

export default function Authority() {
  const nav = useNavigate();
  const [me, setMe] = useState(null);
  const [dash, setDash] = useState(null);
  const [seats, setSeats] = useState([]);
  const [applicants, setApplicants] = useState([]);
  const [results, setResults] = useState([]);
  const [classes, setClasses] = useState([]);
  const [form, setForm] = useState({ class_level: '', shift: 'DAY', seat_gender: 'BOTH', total: '' });
  const [nc, setNc] = useState({ class_level: '', min_dob: '', max_dob: '' });
  const [err, setErr] = useState('');
  const [msg, setMsg] = useState('');

  async function loadAll() {
    setErr('');
    try {
      const [m, d, s, a, r, ce] = await Promise.all([
        api.get('/authority/me'), api.get('/authority/dashboard'),
        api.get('/authority/seats'), api.get('/authority/applicants'), api.get('/authority/results'),
        api.get('/authority/class-eligibility'),
      ]);
      setMe(m.data); setDash(d.data); setSeats(s.data); setApplicants(a.data); setResults(r.data);
      setClasses(ce.data);
    } catch (e) { setErr(apiError(e)); }
  }
  useEffect(() => { loadAll(); }, []);

  // Local date parts, not toISOString(): the API sends dates as UTC instants, so
  // toISOString() would shift them a day back here and re-save the wrong window.
  const isoDate = (d) => {
    const x = new Date(d);
    return `${x.getFullYear()}-${String(x.getMonth() + 1).padStart(2, '0')}-${String(x.getDate()).padStart(2, '0')}`;
  };

  async function addSeat(e) {
    e.preventDefault(); setErr(''); setMsg('');
    try {
      const { data } = await api.post('/authority/seats', {
        class_level: Number(form.class_level), shift: form.shift,
        seat_gender: form.seat_gender, total: Number(form.total),
      });
      setMsg(`Saved seat ${data.seat_id}.`);
      setForm({ class_level: '', shift: 'DAY', seat_gender: 'BOTH', total: '' });
      loadAll();
    } catch (e) { setErr(apiError(e)); }
  }

  function editSeat(s) {
    setErr(''); setMsg('');
    setForm({
      class_level: String(s.class_level), shift: s.shift,
      seat_gender: s.seat_gender, total: String(s.total_available),
    });
  }

  async function delSeat(s) {
    if (!window.confirm(`Delete the class ${s.class_level} ${s.shift} (${s.seat_gender}) seat row?`)) return;
    setErr(''); setMsg('');
    try { await api.delete(`/authority/seats/${s.seat_id}`); setMsg('Seat row deleted.'); loadAll(); }
    catch (e) { setErr(apiError(e)); }
  }

  // --- This school's own age criteria (may only narrow the national window) ---
  async function saveClass(e) {
    e.preventDefault(); setErr(''); setMsg('');
    try {
      await api.post('/authority/class-eligibility', {
        class_level: Number(nc.class_level), min_dob: nc.min_dob, max_dob: nc.max_dob,
      });
      setMsg(`Class ${nc.class_level} window saved for this school.`);
      setNc({ class_level: '', min_dob: '', max_dob: '' });
      loadAll();
    } catch (e) { setErr(apiError(e)); }
  }

  function editClass(c) {
    setErr(''); setMsg('');
    setNc({ class_level: String(c.class_level), min_dob: isoDate(c.min_dob), max_dob: isoDate(c.max_dob) });
  }

  async function resetClass(level) {
    if (!window.confirm(`Reset class ${level} to the national window?`)) return;
    setErr(''); setMsg('');
    try { await api.delete(`/authority/class-eligibility/${level}`); setMsg(`Class ${level} follows the national window again.`); loadAll(); }
    catch (e) { setErr(apiError(e)); }
  }

  function signOut() { logout(); nav('/login'); }

  return (
    <>
      <div className="card">
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <h2>School Authority — {me?.name || ''} ({me?.eiin})</h2>
          <button className="btn-secondary" onClick={signOut}>Logout</button>
        </div>
        {err && <Alert kind="error">{err}</Alert>}
        {msg && <Alert kind="ok">{msg}</Alert>}
        {dash && (
          <div className="kv">
            <div>Seat rows</div><div>{dash.seat_rows}</div>
            <div>Seats remaining</div><div>{dash.seats_remaining}</div>
            <div>Total choices received</div><div>{dash.total_choices}</div>
            <div>Admitted</div><div>{dash.admitted_count}</div>
          </div>
        )}
      </div>

      <div className="card">
        <h3>Add / update seats</h3>
        <form onSubmit={addSeat} className="row">
          <Field label="Class"><input type="number" min="1" max="12" value={form.class_level} onChange={(e) => setForm({ ...form, class_level: e.target.value })} /></Field>
          <Field label="Shift">
            <select value={form.shift} onChange={(e) => setForm({ ...form, shift: e.target.value })}><option>MORNING</option><option>DAY</option></select>
          </Field>
          <Field label="Seat gender">
            <select value={form.seat_gender} onChange={(e) => setForm({ ...form, seat_gender: e.target.value })}><option>BOTH</option><option>MALE</option><option>FEMALE</option></select>
          </Field>
          <Field label="Total seats"><input type="number" min="0" value={form.total} onChange={(e) => setForm({ ...form, total: e.target.value })} /></Field>
          <div style={{ alignSelf: 'end' }}><button type="submit">Save</button></div>
        </form>
        <p className="help">Total is split across quotas automatically (FF 20% · Area 10% · General 70%).</p>
      </div>

      <div className="card">
        <h3>Seats</h3>
        <p className="help">Edit loads a row into the form above; saving it overwrites that row's total. Delete is blocked once applicants have chosen the seat.</p>
        <table>
          <thead><tr><th>Class</th><th>Shift</th><th>Gender</th><th>Available</th><th>By quota</th><th></th></tr></thead>
          <tbody>
            {seats.map((s) => (
              <tr key={s.seat_id}>
                <td>{s.class_level}</td><td>{s.shift}</td><td>{s.seat_gender}</td><td>{s.total_available}</td>
                <td className="muted">{Object.entries(s.by_quota || {}).map(([k, v]) => `${k}:${v}`).join('  ')}</td>
                <td className="btn-row">
                  <button className="btn-secondary" onClick={() => editSeat(s)}>Edit</button>
                  <button className="btn-danger" onClick={() => delSeat(s)}>Delete</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="card">
        <h3>Our admission age criteria</h3>
        <p className="help">
          The date-of-birth window this school accepts for each class. By default every class follows
          the national window; you may <b>narrow</b> it to your own criteria, never widen it. Applicants
          outside your window are rejected when they pick one of your seats. Age limits are shown at
          1 January of the admission year.
        </p>
        <table>
          <thead><tr><th>Class</th><th>We accept from</th><th>We accept to</th><th>Age limit</th><th>National window</th><th>Source</th><th></th></tr></thead>
          <tbody>
            {classes.map((c) => (
              <tr key={c.class_level}>
                <td>Class {c.class_level}</td>
                <td>{isoDate(c.min_dob)}</td>
                <td>{isoDate(c.max_dob)}</td>
                <td>{c.min_age}-{c.max_age}</td>
                <td className="muted">{isoDate(c.national_min_dob)} … {isoDate(c.national_max_dob)}</td>
                <td>{c.is_custom ? <Badge value="OURS" /> : <span className="muted">national</span>}</td>
                <td className="btn-row">
                  <button className="btn-secondary" onClick={() => editClass(c)}>Edit</button>
                  {c.is_custom && <button className="btn-danger" onClick={() => resetClass(c.class_level)}>Reset</button>}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        <form onSubmit={saveClass} className="row" style={{ marginTop: 12 }}>
          <Field label="Class">
            <select value={nc.class_level} onChange={(e) => setNc({ ...nc, class_level: e.target.value })}>
              <option value="">Select…</option>
              {classes.map((c) => <option key={c.class_level} value={c.class_level}>Class {c.class_level}</option>)}
            </select>
          </Field>
          <Field label="Accept from (earliest DOB)">
            <input type="date" value={nc.min_dob} onChange={(e) => setNc({ ...nc, min_dob: e.target.value })} />
          </Field>
          <Field label="Accept to (latest DOB)">
            <input type="date" value={nc.max_dob} onChange={(e) => setNc({ ...nc, max_dob: e.target.value })} />
          </Field>
          <div style={{ alignSelf: 'end' }} className="btn-row">
            <button type="submit" disabled={!nc.class_level || !nc.min_dob || !nc.max_dob}>Save our window</button>
          </div>
        </form>
      </div>

      <div className="card">
        <h3>Applicants ({applicants.length})</h3>
        <table>
          <thead><tr><th>Applicant ID</th><th>Name</th><th>Class</th><th>Status</th></tr></thead>
          <tbody>
            {applicants.map((a) => (
              <tr key={a.application_id}><td>{a.application_id}</td><td>{a.student_name}</td><td>{a.desired_class}</td><td><Badge value={a.status} /></td></tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="card">
        <h3>Results</h3>
        <table>
          <thead><tr><th>Applicant ID</th><th>Name</th><th>Status</th><th>Quota</th><th>Class</th></tr></thead>
          <tbody>
            {results.map((r) => (
              <tr key={r.application_id}><td>{r.application_id}</td><td>{r.student_name}</td><td><Badge value={r.status} /></td><td>{r.allocated_quota || '—'}</td><td>{r.class_level || '—'}</td></tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
