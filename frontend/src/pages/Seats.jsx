import { useEffect, useMemo, useState } from 'react';
import api, { apiError } from '../api/client';
import { Alert, Field } from '../components/ui.jsx';

// Public vacant-seat browser (the portal's "শুন্য আসনের তথ্য" / vacant seats info).
// Filter by area, class and gender; data comes from vw_seat_availability.
export default function Seats() {
  const [areas, setAreas] = useState([]);
  const [division, setDivision] = useState('');
  const [district, setDistrict] = useState('');
  const [postcode, setPostcode] = useState('');
  const [cls, setCls] = useState('');
  const [gender, setGender] = useState('');
  const [type, setType] = useState('');
  const [rows, setRows] = useState(null);
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    api.get('/lookup/areas').then(({ data }) => setAreas(data)).catch((e) => setErr(apiError(e)));
  }, []);

  const divisions = useMemo(() => [...new Set(areas.map((a) => a.division))], [areas]);
  const districts = useMemo(
    () => [...new Set(areas.filter((a) => a.division === division).map((a) => a.district))],
    [areas, division]);
  const thanas = useMemo(
    () => areas.filter((a) => a.division === division && a.district === district),
    [areas, division, district]);

  async function search() {
    setErr(''); setRows(null); setBusy(true);
    try {
      const params = {};
      if (postcode) params.postcode = postcode;
      if (cls) params.class = cls;
      if (gender) params.gender = gender;
      if (type) params.type = type;
      const { data } = await api.get('/lookup/seats', { params });
      setRows(data);
    } catch (e) { setErr(apiError(e)); } finally { setBusy(false); }
  }

  return (
    <div className="card">
      <h2>Vacant Seats</h2>
      <p className="muted">Browse currently available seats by area, class and gender before you apply.</p>
      {err && <Alert kind="error">{err}</Alert>}
      <div className="row">
        <Field label="Division">
          <select value={division} onChange={(e) => { setDivision(e.target.value); setDistrict(''); setPostcode(''); }}>
            <option value="">All</option>
            {divisions.map((d) => <option key={d}>{d}</option>)}
          </select>
        </Field>
        <Field label="District">
          <select value={district} onChange={(e) => { setDistrict(e.target.value); setPostcode(''); }} disabled={!division}>
            <option value="">All</option>
            {districts.map((d) => <option key={d}>{d}</option>)}
          </select>
        </Field>
        <Field label="Thana / Area">
          <select value={postcode} onChange={(e) => setPostcode(e.target.value)} disabled={!district}>
            <option value="">All</option>
            {thanas.map((a) => <option key={a.postcode} value={a.postcode}>{a.thana} ({a.postcode})</option>)}
          </select>
        </Field>
        <Field label="Class">
          <select value={cls} onChange={(e) => setCls(e.target.value)}>
            <option value="">All</option>
            {Array.from({ length: 12 }, (_, i) => i + 1).map((c) => <option key={c} value={c}>Class {c}</option>)}
          </select>
        </Field>
        <Field label="Gender">
          <select value={gender} onChange={(e) => setGender(e.target.value)}>
            <option value="">All</option>
            <option value="MALE">Male</option>
            <option value="FEMALE">Female</option>
          </select>
        </Field>
        <Field label="School type">
          <select value={type} onChange={(e) => setType(e.target.value)}>
            <option value="">All</option>
            <option value="GOVERNMENT">Government</option>
            <option value="NON_GOVERNMENT">Non-Government</option>
          </select>
        </Field>
        <div style={{ alignSelf: 'end' }}><button onClick={search} disabled={busy}>Search</button></div>
      </div>

      {rows && rows.length === 0 && <p className="muted" style={{ marginTop: 14 }}>No vacant seats match these filters.</p>}
      {rows && rows.length > 0 && (
        <>
          <p className="muted" style={{ marginTop: 14 }}>
            {rows.length} seat group(s) · {rows.reduce((n, r) => n + r.total_available, 0)} seats available
          </p>
          <table>
            <thead><tr><th>School</th><th>EIIN</th><th>Type</th><th>Area</th><th>Class</th><th>Shift</th><th>Gender</th><th>Available</th></tr></thead>
            <tbody>
              {rows.map((r) => (
                <tr key={r.seat_id}>
                  <td>{r.school_name}</td><td>{r.eiin}</td>
                  <td>{r.school_type === 'NON_GOVERNMENT' ? 'Non-Govt' : 'Govt'}</td>
                  <td>{r.thana}, {r.district}</td>
                  <td>{r.class_level}</td><td>{r.shift}</td><td>{r.seat_gender}</td>
                  <td><b>{r.total_available}</b></td>
                </tr>
              ))}
            </tbody>
          </table>
        </>
      )}
    </div>
  );
}
