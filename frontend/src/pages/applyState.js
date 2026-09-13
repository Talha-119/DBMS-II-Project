// Form state for the Apply wizard, kept out of the component so the session
// rules can be reasoned about — and tested — without rendering React.

export const blankArea = { division: '', district: '', thana: '', postcode: '' };
export const blankStatus = { status: '', name: '', msg: '' };

export const empty = {
  // `verified_bc` is the certificate the rest of this object was derived from.
  // It is set only by a successful "Verify & auto-fill"; `bc_no` is whatever is
  // currently typed. When they disagree, the form is stale.
  bc_no: '', verified_bc: '',
  name: '', dob: '', gender: '', father_name: '', mother_name: '', returning: false,
  religion: 'ISLAM', mobile: '',
  otp_sent: false, otp_mobile: '', otp_code: '', otp_verified: false, apply_token: '',
  father_nid: '', mother_nid: '', local_guardian_nid: '',
  father_st: blankStatus, mother_st: blankStatus, local_st: blankStatus,
  desired_class: '', eligibleClasses: [],
  present: { ...blankArea }, present_detail: '',
  permanent: { ...blankArea }, permanent_detail: '',
  prev_school_name: '',
  // Passport photograph. `photo_file` is the File the applicant picked this
  // session and `photo_preview` its local object URL -- local because a
  // first-time applicant has no `student` row yet, so there is nowhere on the
  // server for the image to live until the submit succeeds. `has_stored_photo`
  // is the other case: a returning applicant whose photo is already in the
  // database, which the form displays from the server and refuses to replace.
  photo_file: null, photo_preview: '', photo_err: '', has_stored_photo: false,
  applying: { ...blankArea }, seats: [], choices: [],
  // What the application limits leave this applicant (from
  // /lookup/applicant-limits). Derived from the birth certificate like
  // everything else here, so it is cleared by resetForBc below.
  limits: null,
};

// The birth certificate is the identity the entire form hangs off: name, DOB,
// gender, parents, age-eligible classes, the returning-applicant lock and its
// prefilled profile, and the mobile the OTP was issued against are all derived
// from it. Editing it after verification therefore invalidates everything
// downstream — the same reason changing the mobile invalidates the OTP.
//
// Without this the wizard kept the *previous* certificate's data under the new
// number: verify BC3009 (first-time, fields editable), then type BC3015 over it
// and the form still showed TANVIR AHMED, still unlocked, still holding BC3009's
// guardian NID and verified mobile — while submitting as BC3015. It only failed
// at the very end, inside the guardian check, with an error that pointed at the
// NID rather than at the real cause. The reverse was as bad: going from a locked
// returning applicant to a first-time one left the lock and the old values in
// place.
export function bcChanged(state, raw) {
  return Boolean(state.verified_bc) && String(raw).trim() !== state.verified_bc;
}

// Everything derived from the old certificate goes; only the newly typed number
// survives, and the applicant must verify again before they can continue.
//
export function resetForBc(raw) {
  return { ...empty, bc_no: raw };
}

// A photo preview is an object URL, which the browser keeps alive until it is
// explicitly revoked -- so whenever one is replaced or thrown away (a new file
// picked, the certificate changed, the form reset) the old one is released here
// instead of leaking for the lifetime of the tab. Guarded so this module still
// imports cleanly outside a browser, where URL.revokeObjectURL does not exist.
export function releasePreview(url) {
  if (url && typeof URL !== 'undefined' && URL.revokeObjectURL) URL.revokeObjectURL(url);
}
