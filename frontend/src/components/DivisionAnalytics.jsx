import { useEffect, useState } from 'react';
import api, { apiError } from '../../api/client';

export default function DivisionAnalytics() {
  const [division, setDivision] = useState('Dhaka');
  const [data, setData] = useState(null);
  const [err, setErr] = useState('');

  const divisions = ['Dhaka', 'Chattogram', 'Rajshahi', 'Khulna', 'Barishal', 'Sylhet', 'Rangpur', 'Mymensingh'];

  useEffect(() => {
    if (!division) return;
    setErr('');
    api
      .get(`/admin/analytics/division?division=${division}`)
      .then((res) => setData(res.data))
      .catch((e) => setErr(apiError(e)));
  }, [division]);

  return (
    <>
      <h3 className="mb-2">Division Analytics</h3>
      <div className="mb-4">
        <select value={division} onChange={(e) => setDivision(e.target.value)} className="select">
          {divisions.map((d) => (
            <option key={d} value={d}>
              {d}
            </option>
          ))}
        </select>
      </div>
      {err && <div className="alert error">{err}</div>}
      {data && (
        <div>
          <div className="grid grid-cols-3 gap-4 mb-4">
            <div className="card p-4">
              <h4>Total Choices</h4>
              <p>{data[0]?.total_choices ?? 0}</p>
            </div>
            <div className="card p-4">
              <h4>1st Choice %</h4>
              <p>{(data[0]?.choice1_pct ?? 0).toFixed(2)}%</p>
            </div>
            <div className="card p-4">
              <h4>Demand / Seat Ratio</h4>
              <p>{(data[0]?.demand_ratio ?? 0).toFixed(2)}</p>
            </div>
          </div>
          <table className="table w-full">
            <thead>
              <tr>
                <th>EIIN</th>
                <th>School</th>
                <th>Capacity</th>
                <th>Choice 1 Hits</th>
                <th>Total Hits</th>
              </tr>
            </thead>
            <tbody>
              {data.map((row) => (
                <tr key={row.eiin}>
                  <td>{row.eiin}</td>
                  <td>{row.school_name}</td>
                  <td>{row.capacity}</td>
                  <td>{row.choice1_hits}</td>
                  <td>{row.total_hits}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}
