import { useState, useEffect, useRef } from 'react';
import api, { apiError } from '../api/client';
import { Alert, Stepper, Field, Combobox } from '../components/ui.jsx';

const STEPS = ['Birth Certificate', 'Mobile & OTP', 'Guardians', 'Class & Address', 'Schools & Choices', 'Review'];
const RELIGIONS = ['ISLAM', 'HINDU', 'CHRISTIAN', 'BUDDHIST', 'OTHER'];
const MOBILE_RE = /^01[3-9][0-9]{8}$/;
const norm = (s) => (s || '').trim().toUpperCase().replace(/\s+/g, ' ');
const blankArea = { division: '', district: '', thana: '', postcode: '' };
const blankStatus = { status: '', name: '', msg: '' };

const empty = {
  bc_no: '', name: '', dob: '', gender: '', father_name: '', mother_name: '', returning: false,
  religion: 'ISLAM', mobile: '',
  otp_sent: false, otp_mobile: '', otp_code: '', otp_verified: false, apply_token: '',
  father_nid: '', mother_nid: '', local_guardian_nid: '',
  father_st: blankStatus, mother_st: blankStatus, local_st: blankStatus,
  desired_class: '', eligibleClasses: [],
  present: { ...blankArea }, present_detail: '',
  permanent: { ...blankArea }, permanent_detail: '',
  prev_school_name: '',
  applying: { ...blankArea }, seats: [], choices: [],
};

// Build in-memory geography helpers from the /lookup/areas rows (only DB values).
function buildGeo(rows) {
  const divisions = [...new Set(rows.map((r) => r.division))].sort();
  const areaByPostcode = {};
  for (const r of rows) areaByPostcode[r.postcode] = { division: r.division, district: r.district, thana: r.thana };
  return {
    rows, divisions, areaByPostcode,
    districtsOf: (div) => [...new Set(rows.filter((r) => r.division === div).map((r) => r.district))].sort(),
    thanasOf: (div, dist) => [...new Set(rows.filter((r) => r.division === div && r.district === dist).map((r) => r.thana))].sort(),
    postcodeOf: (div, dist, th) => { const m = rows.find((r) => r.division === div && r.district === dist && r.thana === th); return m ? m.postcode : ''; },
  };
}

// Cascading Division -> District -> Thana + Postcode. Fills either direction and
// re-validates on every change; only values that exist in the DB can be committed.
function AddressPicker({ geo, value, onChange }) {
  if (!geo) return <p className="muted">Loading areas…</p>;
  const districts = value.division ? geo.districtsOf(value.division) : [];
  const thanas = (value.division && value.district) ? geo.thanasOf(value.division, value.district) : [];
  const setPostcode = (raw) => {
    const pc = raw.replace(/\D/g, '').slice(0, 4);
    const area = geo.areaByPostcode[pc];
    if (pc.length === 4 && area) onChange({ postcode: pc, ...area });
    else onChange({ ...value, postcode: pc });
  };
  const resolved = geo.areaByPostcode[value.postcode];
  const pcErr = value.postcode.length === 4 && !resolved ? 'Not a valid postcode in our system.'
    : (value.postcode.length > 0 && value.postcode.length < 4 ? 'Postcode must be 4 digits.' : '');
  return (
    <>
      <div className="row">
        <Field label="Division">
          <Combobox options={geo.divisions} value={value.division}
            onChange={(d) => onChange({ division: d, district: '', thana: '', postcode: '' })}
            placeholder="Select or type a division" />
        </Field>
        <Field label="District">
          <Combobox options={districts} value={value.district} disabled={!value.division}
            disabledHint="Select a division first"
            onChange={(d) => onChange({ ...value, district: d, thana: '', postcode: '' })}
            placeholder="Select or type a district" />
        </Field>
      </div>
      <div className="row">
        <Field label="Thana / Upazila">
          <Combobox options={thanas} value={value.thana} disabled={!value.district}
            disabledHint="Select a district first"
            onChange={(t) => onChange({ ...value, thana: t, postcode: geo.postcodeOf(value.division, value.district, t) || '' })}
            placeholder="Select or type a thana" />
        </Field>
        <Field label="Postcode" help="Type a 4-digit postcode to auto-fill the above, or pick from the dropdowns.">
          <input value={value.postcode} inputMode="numeric" maxLength={4} placeholder="e.g. 1000"
            className={pcErr ? 'invalid' : (resolved ? 'valid' : '')}
            onChange={(e) => setPostcode(e.target.value)} />
          {pcErr && <div className="field-err">{pcErr}</div>}
          {resolved && <div className="field-ok">✓ {resolved.thana}, {resolved.district}, {resolved.division}</div>}
        </Field>
      </div>
    </>
  );
}

export default function Apply() {
  const [step, setStep] = useState(0);
  const [f, setF] = useState(empty);
  const [err, setErr] = useState('');
  const [msg, setMsg] = useState('');
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(null);
  const [submitErr, setSubmitErr] = useState([]);
  const [geo, setGeo] = useState(null);
  const [schoolNames, setSchoolNames] = useState([]);

  const fRef = useRef(f); fRef.current = f;
  const ffTimers = useRef({});

  const up = (patch) => setF((s) => ({ ...s, ...patch }));
  const clear = () => { setErr(''); setMsg(''); };

  // Load geography + school names once (drives the dropdowns / suggestions).
  useEffect(() => {
    api.get('/lookup/areas').then((r) => setGeo(buildGeo(r.data))).catch(() => {});
    api.get('/lookup/schools').then((r) => setSchoolNames([...new Set(r.data.map((s) => s.name))].sort())).catch(() => {});
  }, []);

  // If addresses were pre-filled (returning applicant) before geo loaded, resolve them.
  useEffect(() => {
    if (!geo) return;
    ['present', 'permanent', 'applying'].forEach((k) => {
      const a = f[k];
      if (a && a.postcode && !a.division && geo.areaByPostcode[a.postcode]) up({ [k]: { postcode: a.postcode, ...geo.areaByPostcode[a.postcode] } });
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [geo]);

  // --- Live guardian NID validation (debounced; re-checks whenever the NID or the
  //     birth-certificate name changes, so a stale ✓ can never survive an edit). ---
  async function fetchNidStatus(nid, bcName, requireMatch) {
    try {
      const { data } = await api.get(`/lookup/nid/${encodeURIComponent(nid)}`);
      if (!requireMatch) return { status: 'ok', name: data.name, msg: '' };
      return norm(data.name) === norm(bcName)
        ? { status: 'ok', name: data.name, msg: '' }
        : { status: 'err', name: data.name, msg: `This NID belongs to ${data.name}, which does not match the birth-certificate name (${bcName}).` };
    } catch { return { status: 'err', name: '', msg: `NID ${nid} was not found in the registry.` }; }
  }
  function debouncedNidCheck(nid, stField, bcName, requireMatch) {
    if (!nid) { up({ [stField]: blankStatus }); return undefined; }
    up({ [stField]: { status: 'checking', name: '', msg: 'Checking…' } });
    let alive = true;
    const t = setTimeout(async () => {
      const st = await fetchNidStatus(nid, bcName, requireMatch);
      if (alive) up({ [stField]: st });
    }, 350);
    return () => { alive = false; clearTimeout(t); };
  }
  useEffect(() => debouncedNidCheck(f.father_nid.trim(), 'father_st', f.father_name, true),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [f.father_nid, f.father_name]);
  useEffect(() => debouncedNidCheck(f.mother_nid.trim(), 'mother_st', f.mother_name, true),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [f.mother_nid, f.mother_name]);
  useEffect(() => debouncedNidCheck(f.local_guardian_nid.trim(), 'local_st', '', false),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [f.local_guardian_nid]);

  // Re-validate any Freedom-Fighter references when a parent NID changes.
  useEffect(() => {
    fRef.current.choices.forEach((c) => { if (c.ff_on && (c.ref_id || '').trim()) scheduleFfValidate(c.seat_id); });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [f.father_nid, f.mother_nid]);

  async function verifyBC() {
    clear(); setBusy(true);
    try {
      const bc = f.bc_no.trim();
      const { data } = await api.get(`/lookup/birth-cert/${encodeURIComponent(bc)}`);
      const elig = await api.get(`/lookup/eligible-classes?dob=${data.dob.slice(0, 10)}`);
      const patch = {
        name: data.name, dob: data.dob.slice(0, 10), gender: data.gender,
        father_name: data.father_name, mother_name: data.mother_name,
        eligibleClasses: elig.data, returning: false,
      };
      // Returning applicant: same person, same personal details -> pre-fill them.
      try {
        const { data: st } = await api.get(`/lookup/student/${encodeURIComponent(bc)}`);
        const areaFor = (pc) => (geo && geo.areaByPostcode[pc]) ? { postcode: pc, ...geo.areaByPostcode[pc] } : { ...blankArea, postcode: pc || '' };
        patch.returning = true;
        patch.religion = st.religion; patch.mobile = st.mobile || '';
        patch.father_nid = st.father_nid || ''; patch.mother_nid = st.mother_nid || ''; patch.local_guardian_nid = st.local_guardian_nid || '';
        patch.present = areaFor(st.present_postcode); patch.present_detail = st.present_detail || '';
        patch.permanent = areaFor(st.permanent_postcode); patch.permanent_detail = st.permanent_detail || '';
      } catch { /* first-time applicant — nothing to pre-fill */ }
      up(patch);
      setMsg(patch.returning
        ? `Welcome back, ${data.name}. Your saved personal details are pre-filled — just verify your mobile (OTP) and pick your new area & schools.`
        : `Verified: ${data.name} (${data.gender}, born ${data.dob.slice(0, 10)}).`);
    } catch (e) { setErr(apiError(e)); } finally { setBusy(false); }
  }

  async function sendOtp() {
    clear(); setBusy(true);
    try {
      const { data } = await api.post('/otp/send', { mobile: f.mobile, purpose: 'APPLY' });
      up({ otp_sent: true, otp_mobile: f.mobile, otp_verified: false, apply_token: '', otp_code: '' });
      setMsg(`OTP sent to ${data.mobile_masked}.` + (data.dev_code ? ` [DEMO code: ${data.dev_code}]` : ''));
    } catch (e) { setErr(apiError(e)); } finally { setBusy(false); }
  }
  async function confirmOtp() {
    clear(); setBusy(true);
    try {
      const { data } = await api.post('/applications/verify-otp', { mobile: f.mobile, code: f.otp_code });
      up({ otp_verified: true, apply_token: data.token, otp_mobile: f.mobile });
      setMsg(`Mobile ${f.mobile} verified.`);
    } catch (e) { up({ otp_verified: false, apply_token: '' }); setErr(apiError(e)); } finally { setBusy(false); }
  }

  async function loadSeats() {
    clear(); setBusy(true);
    try {
      const { data } = await api.get(`/lookup/seats?postcode=${f.applying.postcode}&class=${f.desired_class}&gender=${f.gender}`);
      up({ seats: data });
      if (!data.length) setMsg('No available seats for this area / class / gender.');
    } catch (e) { setErr(apiError(e)); } finally { setBusy(false); }
  }

  function patchChoice(seatId, patch) {
    setF((s) => ({ ...s, choices: s.choices.map((c) => c.seat_id === seatId ? { ...c, ...(typeof patch === 'function' ? patch(c) : patch) } : c) }));
  }
  function addChoice(seat) {
    if (f.choices.length >= 5) { setErr('Maximum 5 choices.'); return; }
    if (f.choices.some((c) => c.seat_id === seat.seat_id)) { setErr('Seat already chosen.'); return; }
    up({ choices: [...f.choices, {
      seat_id: seat.seat_id, school_name: seat.school_name, shift: seat.shift, seat_gender: seat.seat_gender,
      preference: f.choices.length + 1, general: true, area: (f.applying.postcode === f.present.postcode),
      ff_on: false, ref_id: '', ff_st: blankStatus,
    }] });
  }
  function removeChoice(seatId) {
    setF((s) => ({ ...s, choices: s.choices.filter((c) => c.seat_id !== seatId).map((c, i) => ({ ...c, preference: i + 1 })) }));
  }
  function toggleFf(seatId) {
    patchChoice(seatId, (c) => c.ff_on ? { ff_on: false, ref_id: '', ff_st: blankStatus } : { ff_on: true });
  }
  function setFfRef(seatId, raw) {
    const v = raw.toUpperCase().replace(/\s/g, '');
    patchChoice(seatId, { ref_id: v, ff_st: { status: v ? 'checking' : '', name: '', msg: v ? 'Checking…' : '' } });
    scheduleFfValidate(seatId);
  }
  function scheduleFfValidate(seatId) {
    clearTimeout(ffTimers.current[seatId]);
    ffTimers.current[seatId] = setTimeout(async () => {
      const cur = fRef.current;
      const ch = cur.choices.find((c) => c.seat_id === seatId);
      if (!ch || !ch.ff_on) return;
      const ref = (ch.ref_id || '').trim();
      if (!ref) { patchChoice(seatId, { ff_st: blankStatus }); return; }
      try {
        const { data } = await api.get(`/lookup/quota-reference/${encodeURIComponent(ref)}`);
        const father = (cur.father_nid || '').trim(), mother = (cur.mother_nid || '').trim();
        let st;
        if (data.quota_code !== 'FREEDOM_FIGHTER') st = { status: 'err', name: '', msg: `Reference ${ref} is not a Freedom-Fighter reference.` };
        else if (data.nid !== father && data.nid !== mother) st = { status: 'err', name: '', msg: `Reference ${ref} belongs to NID ${data.nid}, not this applicant's father or mother.` };
        else st = { status: 'ok', name: data.nid, msg: '' };
        patchChoice(seatId, { ff_st: st });
      } catch { patchChoice(seatId, { ff_st: { status: 'err', name: '', msg: `Reference ${ref} was not found in the registry.` } }); }
    }, 400);
  }

  // --- Derived validity used to gate each step + the final submit ---
  const mobileValid = MOBILE_RE.test(f.mobile);
  const mobileErr = !f.mobile ? '' : (f.mobile.length < 11 ? 'Mobile must be 11 digits.' : (!mobileValid ? 'Not a valid Bangladeshi mobile (must start 013–019).' : ''));
  const otpDone = f.otp_verified && f.mobile === f.otp_mobile;
  const guardiansEntered = !!(f.father_nid.trim() || f.mother_nid.trim() || f.local_guardian_nid.trim());
  const guardianBusyOrErr = [f.father_st, f.mother_st, f.local_st].some((s) => s.status === 'err' || s.status === 'checking');
  const guardiansOk = guardiansEntered && !guardianBusyOrErr;
  const presentValid = !!(geo && geo.areaByPostcode[f.present.postcode]);
  const permanentValid = !!(geo && geo.areaByPostcode[f.permanent.postcode]);
  const applyingValid = !!(geo && geo.areaByPostcode[f.applying.postcode]);
  const areaEligible = !!(f.applying.postcode && f.applying.postcode === f.present.postcode);

  const effectiveQuotas = (c) => {
    const q = [];
    if (c.general) q.push('General');
    if (c.area && areaEligible) q.push('Area');
    if (c.ff_on && c.ff_st.status === 'ok') q.push('Freedom Fighter');
    return q.length ? q : ['General'];
  };

  function preSubmitIssues() {
    const x = [];
    if (!otpDone) x.push('Verify the OTP for your current mobile number (Mobile & OTP step).');
    if (!guardiansOk) x.push('Fix the guardian NID(s) — each entered NID must match the birth certificate, and at least one guardian is required (Guardians step).');
    if (!f.desired_class) x.push('Select a desired class (Class & Address step).');
    if (!presentValid || !f.present_detail.trim()) x.push('Complete a valid present address (Class & Address step).');
    if (!permanentValid || !f.permanent_detail.trim()) x.push('Complete a valid permanent address (Class & Address step).');
    if (!applyingValid) x.push('Choose a valid applying area (Schools & Choices step).');
    if (!f.choices.length) x.push('Add at least one school choice (Schools & Choices step).');
    return x;
  }

  async function submit() {
    clear(); setSubmitErr([]);
    const issues = preSubmitIssues();
    if (issues.length) { setSubmitErr(issues); return; }
    setBusy(true);
    try {
      const payload = {
        bc_no: f.bc_no.trim(), religion: f.religion, mobile: f.mobile, apply_token: f.apply_token,
        father_nid: f.father_nid.trim() || null, mother_nid: f.mother_nid.trim() || null,
        local_guardian_nid: f.local_guardian_nid.trim() || null,
        present_postcode: f.present.postcode, present_detail: f.present_detail,
        permanent_postcode: f.permanent.postcode, permanent_detail: f.permanent_detail,
        desired_class: Number(f.desired_class), applying_postcode: f.applying.postcode,
        prev_school_name: f.prev_school_name || null,
        choices: f.choices.map((c) => {
          const q = [];
          if (c.general) q.push({ quota_code: 'GENERAL', ref_id: null });
          if (c.area && areaEligible) q.push({ quota_code: 'AREA', ref_id: null });
          if (c.ff_on && c.ff_st.status === 'ok') q.push({ quota_code: 'FREEDOM_FIGHTER', ref_id: c.ref_id.trim() });
          if (!q.length) q.push({ quota_code: 'GENERAL', ref_id: null });
          return { seat_id: c.seat_id, preference: c.preference, quotas: q };
        }),
      };
      const { data } = await api.post('/applications', payload);
      setDone(data.application_id);
    } catch (e) { setSubmitErr([apiError(e)]); } finally { setBusy(false); }
  }

  const next = () => { clear(); setStep((s) => Math.min(s + 1, STEPS.length - 1)); };
  const back = () => { clear(); setStep((s) => Math.max(s - 1, 0)); };

  if (done) {
    return (
      <div className="card">
        <h2>✅ Application submitted</h2>
        <Alert kind="ok">Your Applicant ID is <b>{done}</b>. Save it. You can download your PDF copy from the “Download / Delete” page.</Alert>
        <div className="btn-row">
          <a className="btn" href={`/retrieve`}>Go to Download</a>
          <button className="btn-secondary" onClick={() => { setF(empty); setStep(0); setDone(null); setSubmitErr([]); }}>New application</button>
        </div>
      </div>
    );
  }

  const nidField = (label, help, nidKey, stKey) => {
    const st = f[stKey];
    return (
      <Field label={label} help={help}>
        <input value={f[nidKey]} inputMode="numeric" maxLength={17} placeholder="e.g. 19910000000000001"
          className={st.status === 'err' ? 'invalid' : (st.status === 'ok' ? 'valid' : '')}
          onChange={(e) => up({ [nidKey]: e.target.value.replace(/\D/g, '') })} />
        {st.status === 'ok' && <div className="field-ok">✓ {st.name}</div>}
        {st.status === 'checking' && <div className="help">Checking…</div>}
        {st.status === 'err' && <div className="field-err">{st.msg}</div>}
      </Field>
    );
  };

  return (
    <div className="card">
      <h2>New Application</h2>
      <Stepper steps={STEPS} current={step} />
      {err && <Alert kind="error">{err}</Alert>}
      {msg && <Alert kind="info">{msg}</Alert>}

      {step === 0 && (
        <>
          <Field label="Birth Certificate Number" help="Try BC3001 … BC3016 in this demo.">
            <input value={f.bc_no} onChange={(e) => up({ bc_no: e.target.value })} placeholder="BC3001" />
          </Field>
          <div className="btn-row">
            <button className={f.bc_no.trim() ? 'btn-ready' : ''} onClick={verifyBC} disabled={busy || !f.bc_no.trim()}>Verify &amp; auto-fill</button>
          </div>
          {f.name && (
            <div className="kv" style={{ marginTop: 14 }}>
              <div>Name</div><div>{f.name}</div>
              <div>Date of Birth</div><div>{f.dob}</div>
              <div>Gender</div><div>{f.gender}</div>
              <div>Father (birth cert)</div><div>{f.father_name}</div>
              <div>Mother (birth cert)</div><div>{f.mother_name}</div>
            </div>
          )}
          <div className="btn-row"><button disabled={!f.name} onClick={next}>Next</button></div>
        </>
      )}

      {step === 1 && (
        <>
          <Field label="Religion">
            <select value={f.religion} onChange={(e) => up({ religion: e.target.value })}>
              {RELIGIONS.map((r) => <option key={r}>{r}</option>)}
            </select>
          </Field>
          <Field label={<>Mobile Number {otpDone && <span className="verified">✓ verified</span>}</>} help="Bangladeshi format: 01XXXXXXXXX (11 digits). Digits only.">
            <input value={f.mobile} inputMode="numeric" maxLength={11} placeholder="01712345678"
              className={f.mobile.length ? (mobileValid ? 'valid' : 'invalid') : ''}
              onChange={(e) => {
                const v = e.target.value.replace(/\D/g, '').slice(0, 11);
                up({ mobile: v, ...(v !== f.otp_mobile ? { otp_sent: false, otp_verified: false, apply_token: '', otp_code: '' } : {}) });
              }} />
            {mobileErr && <div className="field-err">{mobileErr}</div>}
          </Field>
          <div className="btn-row">
            <button className={mobileValid && !otpDone ? 'btn-ready' : 'btn-secondary'} disabled={busy || !mobileValid} onClick={sendOtp}>
              {f.otp_sent ? 'Resend OTP' : 'Send OTP'}
            </button>
          </div>
          {f.otp_sent && !otpDone && (
            <>
              <Field label={`Enter the OTP sent to ${f.otp_mobile}`} help="6-digit code (shown above in this demo). Digits only.">
                <input value={f.otp_code} inputMode="numeric" maxLength={6} placeholder="######"
                  className={f.otp_code.length === 6 ? 'valid' : ''}
                  onChange={(e) => up({ otp_code: e.target.value.replace(/\D/g, '').slice(0, 6) })} />
              </Field>
              <div className="btn-row">
                <button className={f.otp_code.length === 6 ? 'btn-ready' : 'btn-secondary'} disabled={busy || f.otp_code.length !== 6} onClick={confirmOtp}>Verify OTP</button>
              </div>
            </>
          )}
          {otpDone && <Alert kind="ok">Mobile {f.mobile} verified. ✓</Alert>}
          <div className="btn-row">
            <button className="btn-secondary" onClick={back}>Back</button>
            <button onClick={next} disabled={!otpDone}>Next</button>
          </div>
        </>
      )}

      {step === 2 && (
        <>
          <p className="muted">Enter a guardian NID — the registered name is checked live and must match the birth certificate. At least one guardian is required; if no parent is given, a local guardian is mandatory.</p>
          <div className="row">
            {nidField('Father NID', 'Optional — must match the birth-certificate father if given.', 'father_nid', 'father_st')}
            {nidField('Mother NID', 'Optional — must match the birth-certificate mother if given.', 'mother_nid', 'mother_st')}
            {nidField('Local Guardian NID', 'Required only if neither parent is provided.', 'local_guardian_nid', 'local_st')}
          </div>
          <div className="btn-row">
            <button className="btn-secondary" onClick={back}>Back</button>
            <button onClick={next} disabled={!guardiansOk}>Next</button>
          </div>
        </>
      )}

      {step === 3 && (
        <>
          <Field label="Desired Class" help="Only classes your child is age-eligible for are listed.">
            <select value={f.desired_class} onChange={(e) => up({ desired_class: e.target.value })}>
              <option value="">Select…</option>
              {f.eligibleClasses.map((c) => <option key={c.class_level} value={c.class_level}>Class {c.class_level}</option>)}
            </select>
          </Field>

          <h3>Present Address</h3>
          <AddressPicker geo={geo} value={f.present} onChange={(v) => up({ present: v })} />
          <Field label="Present Address (house / road / area)">
            <input value={f.present_detail} onChange={(e) => up({ present_detail: e.target.value })} placeholder="House 12, Road 3" />
          </Field>

          <h3>Permanent Address</h3>
          <AddressPicker geo={geo} value={f.permanent} onChange={(v) => up({ permanent: v })} />
          <Field label="Permanent Address (house / road / area)">
            <input value={f.permanent_detail} onChange={(e) => up({ permanent_detail: e.target.value })} placeholder="House / Road / Area" />
          </Field>

          <Field label="Previous School (optional)" help="Type to search registered schools; if yours isn't listed, just type its name.">
            <Combobox options={schoolNames} value={f.prev_school_name} onChange={(v) => up({ prev_school_name: v })} allowFreeText placeholder="Type a school name" />
          </Field>

          <div className="btn-row">
            <button className="btn-secondary" onClick={back}>Back</button>
            <button onClick={next} disabled={!f.desired_class || !presentValid || !f.present_detail.trim() || !permanentValid || !f.permanent_detail.trim()}>Next</button>
          </div>
        </>
      )}

      {step === 4 && (
        <>
          <h3>Applying School Area</h3>
          <p className="muted">Pick the area you want to apply in, then load its available seats.</p>
          <AddressPicker geo={geo} value={f.applying}
            onChange={(v) => up({ applying: v, ...(v.postcode !== f.applying.postcode ? { choices: [], seats: [] } : {}) })} />
          <div className="btn-row">
            <button className={applyingValid ? 'btn-ready' : 'btn-secondary'} onClick={loadSeats} disabled={busy || !applyingValid}>Load available seats</button>
          </div>
          {areaEligible && <p className="help">Your present address is in this area — you qualify for the <b>Area</b> quota on these choices.</p>}

          {f.seats.length > 0 && (
            <table style={{ marginTop: 12 }}>
              <thead><tr><th>School</th><th>Shift</th><th>Gender</th><th>Available</th><th></th></tr></thead>
              <tbody>
                {f.seats.map((s) => (
                  <tr key={s.seat_id}>
                    <td>{s.school_name}</td><td>{s.shift}</td><td>{s.seat_gender}</td><td>{s.total_available}</td>
                    <td><button className="btn-secondary" onClick={() => addChoice(s)}>Add</button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}

          {f.choices.length > 0 && (
            <>
              <h3>Your choices (in order of preference)</h3>
              <p className="help">Tick every quota you qualify for — the lottery considers you under each, in priority order (FF → Area → General). A quota is only applied once its requirements check out.</p>
              <table>
                <thead><tr><th>#</th><th>School</th><th>Shift</th><th>Quotas</th><th>Freedom-Fighter Ref</th><th></th></tr></thead>
                <tbody>
                  {f.choices.map((c) => (
                    <tr key={c.seat_id}>
                      <td>{c.preference}</td><td>{c.school_name}</td><td>{c.shift}</td>
                      <td>
                        <label className="qk"><input type="checkbox" checked={c.general} onChange={() => patchChoice(c.seat_id, (x) => ({ general: !x.general }))} /> General</label>
                        {areaEligible && <label className="qk"><input type="checkbox" checked={c.area} onChange={() => patchChoice(c.seat_id, (x) => ({ area: !x.area }))} /> Area</label>}
                        <label className="qk"><input type="checkbox" checked={c.ff_on} onChange={() => toggleFf(c.seat_id)} /> FF</label>
                      </td>
                      <td>
                        {c.ff_on ? (
                          <>
                            <input value={c.ref_id} placeholder="FF-1001"
                              className={c.ff_st.status === 'err' ? 'invalid' : (c.ff_st.status === 'ok' ? 'valid' : '')}
                              onChange={(e) => setFfRef(c.seat_id, e.target.value)} />
                            {c.ff_st.status === 'ok' && <div className="field-ok">✓ valid FF reference</div>}
                            {c.ff_st.status === 'checking' && <div className="help">Checking…</div>}
                            {c.ff_st.status === 'err' && <div className="field-err">{c.ff_st.msg} FF will be skipped.</div>}
                          </>
                        ) : <span className="muted">—</span>}
                      </td>
                      <td><button className="btn-danger" onClick={() => removeChoice(c.seat_id)}>Remove</button></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </>
          )}
          <div className="btn-row">
            <button className="btn-secondary" onClick={back}>Back</button>
            <button onClick={next} disabled={f.choices.length === 0}>Review</button>
          </div>
        </>
      )}

      {step === 5 && (
        <>
          <p className="muted">Please review your application below exactly as it will be recorded. Confirm to submit, or go back to edit any section.</p>
          <div className="doc">
            <h3 className="doc-title">Government School Admission System</h3>
            <p className="doc-sub">Applicant Copy — Preview (not yet submitted)</p>

            <h4>Student (from Birth Certificate)</h4>
            <div className="doc-row"><b>Birth Certificate No</b><span>{f.bc_no}</span></div>
            <div className="doc-row"><b>Name</b><span>{f.name}</span></div>
            <div className="doc-row"><b>Date of Birth</b><span>{f.dob}</span></div>
            <div className="doc-row"><b>Gender</b><span>{f.gender}</span></div>
            <div className="doc-row"><b>Religion</b><span>{f.religion}</span></div>
            <div className="doc-row"><b>Mobile</b><span>{f.mobile} {otpDone && <span className="verified">✓ verified</span>}</span></div>

            <h4>Guardians</h4>
            <div className="doc-row"><b>Father</b><span>{f.father_nid ? `${f.father_st.name || ''} (NID: ${f.father_nid})` : '—'}</span></div>
            <div className="doc-row"><b>Mother</b><span>{f.mother_nid ? `${f.mother_st.name || ''} (NID: ${f.mother_nid})` : '—'}</span></div>
            <div className="doc-row"><b>Local Guardian</b><span>{f.local_guardian_nid ? `${f.local_st.name || ''} (NID: ${f.local_guardian_nid})` : '—'}</span></div>

            <h4>Admission</h4>
            <div className="doc-row"><b>Desired Class</b><span>{f.desired_class}</span></div>
            <div className="doc-row"><b>Previous School</b><span>{f.prev_school_name || '—'}</span></div>

            <h4>Addresses</h4>
            <div className="doc-row"><b>Present</b><span>{f.present_detail}{f.present.postcode ? `, ${f.present.thana}, ${f.present.district}, ${f.present.division} (${f.present.postcode})` : ''}</span></div>
            <div className="doc-row"><b>Permanent</b><span>{f.permanent_detail}{f.permanent.postcode ? `, ${f.permanent.thana}, ${f.permanent.district}, ${f.permanent.division} (${f.permanent.postcode})` : ''}</span></div>
            <div className="doc-row"><b>Applying Area</b><span>{f.applying.postcode ? `${f.applying.thana}, ${f.applying.district}, ${f.applying.division} (${f.applying.postcode})` : f.applying.postcode}</span></div>

            <h4>School Choices (in order of preference)</h4>
            <ol className="doc-choices">
              {f.choices.map((c) => {
                const ffDropped = c.ff_on && c.ff_st.status !== 'ok';
                return (
                  <li key={c.seat_id}>
                    {c.school_name} — {c.shift} — Quota: {effectiveQuotas(c).join(', ')}
                    {c.ff_on && c.ff_st.status === 'ok' && c.ref_id ? ` (Ref: ${c.ref_id})` : ''}
                    {ffDropped && <span className="field-err"> — Freedom-Fighter not applied (reference invalid)</span>}
                  </li>
                );
              })}
            </ol>
            <p className="watermark">Identity & guardian data are re-validated against official registries on submission.</p>
          </div>

          {submitErr.length > 0 && (
            <div className="submit-note">
              <Alert kind="error">
                <b>Please fix the following, then submit again:</b>
                <ul style={{ margin: '6px 0 0', paddingLeft: 18 }}>{submitErr.map((x, i) => <li key={i}>{x}</li>)}</ul>
              </Alert>
            </div>
          )}

          <div className="btn-row" style={{ marginTop: 16 }}>
            <button className="btn-secondary" onClick={back}>← Go back &amp; edit</button>
            <button onClick={submit} disabled={busy}>✔ Confirm &amp; Submit</button>
          </div>
        </>
      )}
    </div>
  );
}
