import { Link } from 'react-router-dom';
import { useRoundStatus } from '../api/roundStatus';

export default function Home() {
  // Results exist only once the admin has run the lottery AND pressed publish.
  // Until then the tile is not a link at all — the applicant side must not
  // learn that an allocation already happened.
  const { result_ready: resultReady, ready } = useRoundStatus();

  return (
    <>
      <div className="hero">
        <h1>Government School Admission</h1>
        <p>
          Apply online for Class 1–9 admission. Your identity details are filled automatically from
          official registries (birth certificate, NID, postcode) — so there are no typing mistakes
          and no information mismatch.
        </p>
      </div>

      <div className="tiles">
        <Link to="/apply" className="card tile">
          <h2>New Application</h2>
          <p className="muted">Verify your birth certificate, pick schools, and submit. Get an Applicant ID + PDF copy.</p>
        </Link>
        <Link to="/seats" className="card tile">
          <h2>Vacant Seats</h2>
          <p className="muted">Browse available seats by area, class and gender before applying.</p>
        </Link>
        <Link to="/retrieve" className="card tile">
          <h2>Download / Delete</h2>
          <p className="muted">Retrieve your application with Birth Cert + DOB + mobile OTP. Download the PDF or request deletion.</p>
        </Link>
        {resultReady ? (
          <Link to="/result" className="card tile">
            <h2>Check Result</h2>
            <p className="muted">See your lottery result — merit list and waiting lists.</p>
          </Link>
        ) : (
          <div className="card tile tile-locked" aria-disabled="true">
            <h2>Check Result</h2>
            <p className="muted">Merit list and waiting lists open here once the authority publishes them.</p>
            {ready && <span className="tile-lock-note">Not published yet</span>}
          </div>
        )}
        <Link to="/recover" className="card tile">
          <h2>Recover Applicant ID</h2>
          <p className="muted">Forgot your Applicant ID? Recover it with your Birth Cert + mobile OTP.</p>
        </Link>
      </div>

      <div className="card">
        <h2>Demo data (for testing)</h2>
        <p className="muted">This is a course demo. OTP codes are shown on screen instead of being sent by SMS.</p>
        <ul className="muted">
          <li>Sample birth-certificate numbers: <b>BC3001 … BC3012</b> (e.g. BC3001 is age-eligible for Class 3).</li>
          <li>Areas: <b>1000</b> Motijheel, <b>1206</b> Cantonment, <b>1217</b> Ramna.</li>
          <li>Staff: master admin <b>admin / admin123</b>; school authority <b>108103 / school123</b>.</li>
        </ul>
      </div>
    </>
  );
}
