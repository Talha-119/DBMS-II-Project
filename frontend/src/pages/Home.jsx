import { Link } from 'react-router-dom';

export default function Home() {
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
          <h2>📝 New Application</h2>
          <p className="muted">Verify your birth certificate, pick schools, and submit. Get an Applicant ID + PDF copy.</p>
        </Link>
        <Link to="/retrieve" className="card tile">
          <h2>⬇️ Download / Delete</h2>
          <p className="muted">Retrieve your application with Birth Cert + DOB + mobile OTP. Download the PDF or request deletion.</p>
        </Link>
        <Link to="/result" className="card tile">
          <h2>🎯 Check Result</h2>
          <p className="muted">See your lottery result once admissions are published.</p>
        </Link>
        <Link to="/recover" className="card tile">
          <h2>🔑 Recover Applicant ID</h2>
          <p className="muted">Forgot your Applicant ID? Recover it with your Birth Cert + mobile OTP.</p>
        </Link>
      </div>

      <div className="card">
        <h2>Demo data (for testing)</h2>
        <p className="muted">This is a course demo. OTP codes are shown on screen instead of being sent by SMS.</p>
        <ul className="muted">
          <li>Sample birth-certificate numbers: <b>BC3001 … BC3016</b> (e.g. BC3001 is age-eligible for Class 3).</li>
          <li>Areas: <b>1000</b> Motijheel, <b>1206</b> Cantonment, <b>1217</b> Ramna, <b>1212</b> Gulshan.</li>
        </ul>
      </div>
    </>
  );
}
