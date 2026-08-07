import { useState, useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import api, { apiError, setToken, setRole, getToken, getRole } from '../api/client';
import { Alert, Field } from '../components/ui.jsx';

// Staff login (school authority / master admin). Password verified in the DB.
// ?type=GOVERNMENT|NON_GOVERNMENT preselects the track heading, mirroring the
// portal's separate government / non-government authority login pages.
export default function Login() {
  const [params] = useSearchParams();
  const track = params.get('type');
  const [loginId, setLoginId] = useState('');
  const [password, setPassword] = useState('');
  const [err, setErr] = useState('');
  const [busy, setBusy] = useState(false);
  const nav = useNavigate();
useEffect(() => {
  const token = getToken();
  const role = getRole();
  if (token && role) {
    nav(role === 'MASTER_ADMIN' ? '/admin' : '/authority');
  }
}, []);
  async function submit(e) {
    e.preventDefault();
    setErr(''); setBusy(true);
    try {
      const { data } = await api.post('/auth/login', { login_id: loginId.trim(), password });
      setToken(data.token); setRole(data.role);
      nav(data.role === 'MASTER_ADMIN' ? '/admin' : '/authority');
    } catch (e) { setErr(apiError(e)); } finally { setBusy(false); }
  }

  return (
    <div className="card" style={{ maxWidth: 420, margin: '0 auto' }}>
      <h2>{track ? `${track === 'GOVERNMENT' ? 'Government' : 'Non-Government'} School Authority Login` : 'Staff Login'}</h2>
      <p className="muted">
        {track === 'NON_GOVERNMENT'
          ? <>Non-government school authority. Demo: <b>200002 / school123</b> (login = EIIN).</>
          : <>Master admin or school authority. Demo: <b>admin / admin123</b> or <b>108103 / school123</b>.</>}
      </p>
      {err && <Alert kind="error">{err}</Alert>}
      <form onSubmit={submit}>
        <Field label="Login ID (username or EIIN)"><input value={loginId} onChange={(e) => setLoginId(e.target.value)} autoComplete="username" /></Field>
        <Field label="Password"><input type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="current-password" /></Field>
        <button type="submit" disabled={busy || !loginId || !password}>Login</button>
      </form>
    </div>
  );
}
