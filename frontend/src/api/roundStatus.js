import { useEffect, useState } from 'react';
import api from './client';

// Public admission status: is the application window open, and have the lottery
// results been published? Both are admin-controlled switches, and the public
// pages (landing tiles, the result lookup, the nav) must follow them — running
// the lottery produces results that stay invisible here until the admin
// presses "Publish results".
//
// `ready` distinguishes "not published" from "not loaded yet", so a page can
// avoid flashing a "results are not out" notice while the request is in flight.
// A failed request leaves the flags false (closed / unpublished): the backend
// is the real gate, so the cautious reading is the right one to render.
export function useRoundStatus() {
  const [status, setStatus] = useState({ round_open: false, result_ready: false, current_round: 0 });
  const [ready, setReady] = useState(false);

  useEffect(() => {
    let alive = true;
    api.get('/lookup/round-status')
      .then(({ data }) => { if (alive) setStatus(data); })
      .catch(() => {})
      .finally(() => { if (alive) setReady(true); });
    return () => { alive = false; };
  }, []);

  return { ...status, ready };
}
