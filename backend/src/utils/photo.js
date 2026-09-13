'use strict';
// Applicant photograph: accept an upload, prove it is really an image, and
// normalize it to one fixed representation before it is ever stored.
//
// Postgres cannot do any of this. It cannot decode an image, so it cannot tell a
// JPEG from a renamed executable, cannot measure the picture, cannot crop it and
// cannot re-encode it -- none of that is built in, and no common extension adds
// it. So the whole pipeline runs here, in Node, and the database is handed bytes
// that are already known-good (it then re-checks the cheap parts itself:
// fn_is_jpeg and chk_student_photo_size in database/).
const multer = require('multer');
const sharp = require('sharp');

// 35mm x 45mm is the Bangladeshi passport-photo format: a 7:9 portrait.
// 300 x 386 is that ratio at roughly 220dpi -- sharp enough for the ~90pt-wide
// slot on the printed applicant copy, small enough that the JPEG below lands
// around 20-30KB.
const PHOTO_W = 300;
const PHOTO_H = 386;
const JPEG_QUALITY = 82;

// Floor on the *source* image. Anything smaller is being upscaled into a
// passport photo, which produces a blurred rectangle rather than a usable face,
// so it is refused instead of silently accepted.
const MIN_SOURCE_SIDE = 200;

// What multer will read off the wire at all. Deliberately much larger than the
// stored bound: a straight-off-a-phone photo is several MB and is perfectly
// legitimate input -- it is the *output* of the resize that has to be small.
const MAX_UPLOAD_BYTES = 8 * 1024 * 1024;

// Mirrors chk_student_photo_size in database/migrations/004_application.sql. The
// re-encode above cannot realistically reach this, so tripping it means the
// pipeline changed and the two bounds have drifted apart.
const MAX_STORED_BYTES = 512 * 1024;

const ACCEPTED_FORMATS = ['jpeg', 'png'];

function badRequest(message) {
  const e = new Error(message);
  e.status = 400;
  return e;
}

// memoryStorage: the bytes are re-encoded and handed to Postgres, so they never
// need to touch the filesystem -- there is no upload directory to secure, to
// back up, or to leave orphaned files in.
const uploader = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_UPLOAD_BYTES, files: 1, fields: 40 },
}).single('photo');

// Multer is a no-op on a request that is not multipart/form-data, so this can sit
// on a route that still accepts plain JSON. Its own errors are translated here
// rather than left to the generic handler, which would surface multer's terse
// "File too large" with no indication of the limit.
function photoUpload(req, res, next) {
  uploader(req, res, (err) => {
    if (!err) return next();
    if (err.code === 'LIMIT_FILE_SIZE') {
      return next(badRequest(
        `That photo is larger than ${Math.round(MAX_UPLOAD_BYTES / (1024 * 1024))}MB. Please upload a smaller image.`));
    }
    if (err.code === 'LIMIT_FILE_COUNT' || err.code === 'LIMIT_UNEXPECTED_FILE') {
      return next(badRequest('Only one photograph may be attached, in a field named "photo".'));
    }
    return next(badRequest('The uploaded photograph could not be read.'));
  });
}

// Decode -> validate -> flatten -> crop -> re-encode. Returns the JPEG buffer to
// store, or throws a 400 naming what was wrong with the file.
async function normalizePhoto(buffer) {
  if (!buffer || !buffer.length) throw badRequest('The uploaded photograph was empty.');

  // metadata() decodes the real file header, so a .jpg extension or a forged
  // Content-Type proves nothing here -- what the bytes actually are is what is
  // checked.
  let meta;
  try {
    meta = await sharp(buffer).metadata();
  } catch {
    throw badRequest('That file is not a readable image. Please upload a JPEG or PNG photograph.');
  }

  if (!ACCEPTED_FORMATS.includes(meta.format)) {
    throw badRequest(
      `The photograph must be a JPEG or PNG image${meta.format ? ` (this file is ${meta.format.toUpperCase()})` : ''}.`);
  }

  // EXIF-rotated phone photos report their pre-rotation dimensions, so measure
  // the image the way it will actually be displayed.
  const upright = meta.orientation >= 5 && meta.orientation <= 8;
  const width = upright ? meta.height : meta.width;
  const height = upright ? meta.width : meta.height;
  if (!width || !height) throw badRequest('The photograph has no readable dimensions.');
  if (width < MIN_SOURCE_SIDE || height < MIN_SOURCE_SIDE) {
    throw badRequest(
      `The photograph is too small (${width}x${height} pixels). It must be at least ${MIN_SOURCE_SIDE}x${MIN_SOURCE_SIDE}.`);
  }

  const out = await sharp(buffer)
    // Apply the EXIF orientation first, so a portrait shot taken sideways is
    // cropped upright instead of having its face cut off at the edge.
    .rotate()
    // PNG may carry an alpha channel; JPEG has none, so transparency would
    // otherwise be composited onto black when the copy is printed. JPEG input
    // has nothing to flatten, so this is a no-op there.
    .flatten({ background: '#ffffff' })
    // fit: 'cover' both downscales and centre-crops, and always emits exactly
    // PHOTO_W x PHOTO_H -- so one call handles an oversized image, a landscape
    // one, and a square one, and the stored aspect ratio is never in doubt.
    .resize(PHOTO_W, PHOTO_H, { fit: 'cover', position: 'center' })
    // Re-encoded as JPEG whatever came in. This is what lets student.photo, the
    // serving endpoint and the PDF all assume one format with no mime column.
    .jpeg({ quality: JPEG_QUALITY, mozjpeg: true })
    .toBuffer();

  if (out.length > MAX_STORED_BYTES) {
    throw badRequest('The photograph could not be reduced to an acceptable size. Please upload a simpler image.');
  }
  return out;
}

module.exports = {
  photoUpload,
  normalizePhoto,
  PHOTO_W,
  PHOTO_H,
  MIN_SOURCE_SIDE,
  MAX_UPLOAD_BYTES,
  MAX_STORED_BYTES,
};
