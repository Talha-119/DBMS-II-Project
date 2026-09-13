'use strict';
const PDFDocument = require('pdfkit');

// The passport-photo slot on the printed form, in PDF points. 90 x 116 is the
// 7:9 shape the stored image already has (see utils/photo.js), so PDFKit scales
// it without distorting the face. It sits in the top-right corner beside the
// header, which is where a real admission form puts it.
const PHOTO_BOX = { x: 450, y: 50, w: 90, h: 116 };

// Render the official "Applicant Copy" PDF from a vw_applicant_copy row and pipe
// it to the HTTP response. `photo` is the JPEG from student.photo, or null for an
// applicant who has none -- in which case the slot is printed empty rather than
// omitted, so both copies are the same document with the same layout.
function streamApplicantCopy(copy, res, photo) {
  const doc = new PDFDocument({ size: 'A4', margin: 50 });
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `attachment; filename="${copy.application_id}.pdf"`);
  doc.pipe(res);

  const line = (y) => doc.moveTo(50, y).lineTo(545, y).strokeColor('#cccccc').stroke().strokeColor('black');

  // Header. Centred inside a width that stops short of the photo box, so the
  // title cannot run underneath the photograph.
  const headWidth = PHOTO_BOX.x - 50 - 10;
  doc.fontSize(16).font('Helvetica-Bold').text('Government School Admission System', 50, 50, { width: headWidth, align: 'center' });
  doc.fontSize(11).font('Helvetica').fillColor('#555')
     .text('Directorate of Secondary and Higher Education', 50, doc.y, { width: headWidth, align: 'center' });
  doc.fillColor('black').moveDown(0.3);
  doc.fontSize(13).font('Helvetica-Bold').text('APPLICANT COPY', 50, doc.y, { width: headWidth, align: 'center' });

  // Photograph slot. Drawn as a bordered box either way: a form with an empty
  // photo box reads as "no photo was supplied", whereas a form that silently
  // omits the box reads as though it never asked for one.
  doc.rect(PHOTO_BOX.x, PHOTO_BOX.y, PHOTO_BOX.w, PHOTO_BOX.h).lineWidth(0.8).strokeColor('#999').stroke();
  if (photo && photo.length) {
    // The stored image is already exactly this aspect ratio, so `fit` scales it
    // to fill the box without letterboxing; `align`/`valign` keep it centred if
    // a future size change ever makes the ratios differ.
    doc.image(photo, PHOTO_BOX.x, PHOTO_BOX.y, {
      fit: [PHOTO_BOX.w, PHOTO_BOX.h], align: 'center', valign: 'center',
    });
  } else {
    doc.font('Helvetica').fontSize(8).fillColor('#999')
       .text('No photograph on file', PHOTO_BOX.x + 4, PHOTO_BOX.y + PHOTO_BOX.h / 2 - 10,
             { width: PHOTO_BOX.w - 8, align: 'center' });
  }
  doc.strokeColor('black').fillColor('black');

  // Everything after the header runs the full width again, so it has to start
  // below the photo box rather than beside it.
  doc.x = 50;
  doc.y = Math.max(doc.y + 6, PHOTO_BOX.y + PHOTO_BOX.h + 10);
  line(doc.y); doc.moveDown(0.5);

  const fmtDate = (d) => (d ? new Date(d).toISOString().slice(0, 10) : '');

  // Two-column field printer.
  function field(label, value) {
    const startY = doc.y;
    doc.font('Helvetica-Bold').fontSize(10).text(label + ':', 55, startY, { width: 160, continued: false });
    doc.font('Helvetica').fontSize(10).text(value == null || value === '' ? '-' : String(value), 220, startY, { width: 320 });
    doc.moveDown(0.3);
  }

  function section(title) {
    doc.moveDown(0.4);
    doc.font('Helvetica-Bold').fontSize(11).fillColor('#1a3e72').text(title);
    doc.fillColor('black').moveDown(0.2);
  }

  section('Application');
  field('Application ID', copy.application_id);
  field('Status', copy.status);
  field('Submitted At', copy.submitted_at ? new Date(copy.submitted_at).toLocaleString() : '');
  field('Desired Class', copy.desired_class);
  field('Fee Status', copy.payment_status ? `${copy.payment_status}${copy.fee_amount ? ` (${copy.fee_amount})` : ''}` : '-');

  section('Student (from Birth Certificate)');
  field('Birth Certificate No', copy.bc_no);
  field('Name', copy.student_name);
  field('Date of Birth', fmtDate(copy.dob));
  field('Gender', copy.gender);
  field('Religion', copy.religion);
  field('Mobile', copy.mobile);

  section('Guardians');
  field('Father', copy.father_name ? `${copy.father_name} (NID: ${copy.father_nid})` : '-');
  field('Mother', copy.mother_name ? `${copy.mother_name} (NID: ${copy.mother_nid})` : '-');
  field('Local Guardian', copy.local_guardian_name ? `${copy.local_guardian_name} (NID: ${copy.local_guardian_nid})` : '-');

  section('Addresses');
  field('Present', `${copy.present_detail}, ${copy.present_thana}, ${copy.present_district}, ${copy.present_division} (${copy.present_postcode})`);
  field('Permanent', `${copy.permanent_detail}, ${copy.permanent_thana}, ${copy.permanent_district}, ${copy.permanent_division} (${copy.permanent_postcode})`);
  field('Applying Area', `${copy.applying_thana}, ${copy.applying_district}, ${copy.applying_division} (${copy.applying_postcode})`);

  section('School Choices');
  const choices = Array.isArray(copy.choices) ? copy.choices : [];
  if (!choices.length) {
    doc.font('Helvetica').fontSize(10).text('No choices recorded.', 55);
  } else {
    choices.forEach((c) => {
      const quotas = Array.isArray(c.quotas) ? c.quotas.join(', ') : (c.quota || '');
      doc.font('Helvetica').fontSize(10).text(
        `${c.preference}. ${c.school_name}  |  Class ${c.class}  |  ${c.shift}  |  ${c.seat_gender}  |  Quota: ${quotas}`,
        55, doc.y, { width: 490 }
      );
      doc.moveDown(0.2);
    });
  }

  doc.moveDown(1);
  line(doc.y); doc.moveDown(0.3);
  doc.fontSize(8).fillColor('#777').text(
    'This is a system-generated applicant copy. Identity fields are sourced from official registries.',
    { align: 'center' }
  );

  doc.end();
}

module.exports = { streamApplicantCopy };
