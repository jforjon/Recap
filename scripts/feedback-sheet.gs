// recap — feedback receiver.
//
// Lives in a Google Sheet's Apps Script project and is published as a web app.
// The iOS app POSTs here; this appends a row and emails a copy.
//
// The sheet is opened by id rather than with getActiveSpreadsheet(), which only
// works when the script is bound to the sheet AND has been authorised for the
// spreadsheet scope. By id it works either way, and the failure mode when
// something is wrong is a clear message instead of a permissions riddle.

// Paste your sheet's URL here (the whole thing is fine).
const SHEET_URL = 'PASTE_YOUR_SHEET_URL_HERE';

// Must match FEEDBACK_SECRET in Recap/Resources/Secrets.xcconfig, which is
// gitignored — this repo is public, so the real value is not written down here.
// It is not a secret in any strong sense (it ships inside the app binary); it
// just keeps drive-by writes out of the sheet.
const SECRET = 'PASTE_FEEDBACK_SECRET_HERE';

/// Run this once from the editor to grant the sheet and mail permissions.
/// Apps Script only asks for what the code needs, so this has to touch both.
function authorise() {
  SpreadsheetApp.openByUrl(SHEET_URL).getName();
  MailApp.getRemainingDailyQuota();
}

function doPost(e) {
  const data = JSON.parse(e.postData.contents);

  // Throw rather than quietly ignore: during setup a mismatch here is a typo,
  // and a silent success would hide it.
  if (data.secret !== SECRET) {
    throw new Error('bad secret');
  }

  const message = String(data.message || '').trim().slice(0, 4000);
  if (!message) {
    throw new Error('empty message');
  }

  const diagnostics = String(data.diagnostics || '');

  SpreadsheetApp.openByUrl(SHEET_URL)
    .getSheets()[0]
    .appendRow([new Date(), message, diagnostics]);

  // Sends to whoever owns this script — you — so no address is written down
  // anywhere, here or in the app.
  MailApp.sendEmail(
    Session.getEffectiveUser().getEmail(),
    'recap feedback',
    message + '\n\n---\n' + diagnostics
  );

  return ContentService.createTextOutput('ok');
}
