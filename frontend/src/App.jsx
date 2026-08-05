import { NavLink, Route, Routes, Navigate } from 'react-router-dom';
import Home from './pages/Home.jsx';
import Apply from './pages/Apply.jsx';
import Retrieve from './pages/Retrieve.jsx';
import Result from './pages/Result.jsx';
import Recover from './pages/Recover.jsx';

export default function App() {
  return (
    <>
      <header className="site-header">
        <div className="bar">
          <NavLink to="/" className="brand">🎓 GSA · School Admission</NavLink>
          <nav>
            <NavLink to="/apply">Apply</NavLink>
            <NavLink to="/retrieve">Download / Delete</NavLink>
            <NavLink to="/result">Result</NavLink>
            <NavLink to="/recover">Recover ID</NavLink>
          </nav>
        </div>
      </header>

      <main>
        <Routes>
          <Route path="/" element={<Home />} />
          <Route path="/apply" element={<Apply />} />
          <Route path="/retrieve" element={<Retrieve />} />
          <Route path="/result" element={<Result />} />
          <Route path="/recover" element={<Recover />} />
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
