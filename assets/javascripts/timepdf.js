// Ensures a 'PDF' link appears next to 'Atom | CSV' on the Spent time page.
document.addEventListener('DOMContentLoaded', function () {
  var m = location.pathname.match(/^\/projects\/([^\/]+)\/time_entries/);
  if (!m) return;
  var projectId = m[1];
  var other = document.querySelector('.other-formats');
  if (!other) return;
  var qs = location.search || '';
  var url = '/projects/' + projectId + '/timepdf/export.pdf' + qs;
  if (!other.textContent.match(/PDF/)) {
    var sep = document.createTextNode(' | ');
    var a = document.createElement('a');
    a.href = url;
    a.textContent = 'PDF';
    a.target = '_blank';
    a.rel = 'noopener';
    other.appendChild(sep);
    other.appendChild(a);
  }
});
