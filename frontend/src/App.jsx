import { NavLink, Route, Routes, Navigate } from 'react-router-dom';
import { getRole, getToken } from './api/client';
import Home from './pages/Home.jsx';
import Apply from './pages/Apply.jsx';
import Seats from './pages/Seats.jsx';
import Retrieve from './pages/Retrieve.jsx';
import Result from './pages/Result.jsx';
import Recover from './pages/Recover.jsx';
import Login from './pages/Login.jsx';
import Authority from './pages/Authority.jsx';
import Admin from './pages/Admin.jsx';

function RequireRole({ role, children }) {
  if (!getToken() || getRole() !== role) return <Navigate to="/login" replace />;
  return children;
}

export default function App() {
  return (
    <>
      <header className="site-header">
        <div className="bar">
          <NavLink to="/" className="brand">🎓 GSA · School Admission</NavLink>
          <nav>
            <NavLink to="/apply">Apply</NavLink>
            <NavLink to="/seats">Vacant Seats</NavLink>
            <NavLink to="/retrieve">Download / Delete</NavLink>
            <NavLink to="/result">Result</NavLink>
            <NavLink to="/recover">Recover ID</NavLink>
            <NavLink to="/login">Admin / School Authority Login</NavLink>
          </nav>
        </div>
      </header>

      <main>
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/apply" element={<Apply />} />
          <Route path="/seats" element={<Seats />} />
          <Route path="/retrieve" element={<Retrieve />} />
          <Route path="/result" element={<Result />} />
          <Route path="/recover" element={<Recover />} />
          <Route path="/login" element={<Login />} />
          <Route path="/authority" element={<RequireRole role="SCHOOL_AUTHORITY"><Authority /></RequireRole>} />
          <Route path="/admin" element={<RequireRole role="MASTER_ADMIN"><Admin /></RequireRole>} />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </main>

      <footer>
        Government School Admission System · DBMS-II project · Identity data is sourced from official
        registries (no manual entry). Demo only.
      </footer>
    </>
  );
}
