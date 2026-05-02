// Injects the PDF export button into the Spent time view.
// Redmine 6's timelog/index.html.erb has no view_timelog_index_* hooks, so the
// plugin renders this script via view_layouts_base_html_head and the script
// places the button into the contextual area and the "Atom | CSV" footer line.
(function () {
  function buildUrl(base) {
    return base + window.location.search;
  }

  function injectContextual(cfg, url) {
    var ctx = document.querySelector('div.contextual');
    if (!ctx || ctx.querySelector('a.timepdf-export-link')) return;
    var a = document.createElement('a');
    a.href = url;
    a.target = '_blank';
    a.rel = 'noopener';
    a.className = 'icon icon-pdf timepdf-export-link';
    a.textContent = cfg.labels.action;
    ctx.appendChild(a);
  }

  function injectOtherFormats(cfg, url) {
    var p = document.querySelector('p.other-formats');
    if (!p || p.querySelector('a.timepdf-format-link')) return;
    p.appendChild(document.createTextNode(' | '));
    var a = document.createElement('a');
    a.href = url;
    a.target = '_blank';
    a.rel = 'noopener';
    a.className = 'timepdf-format-link';
    a.textContent = cfg.labels.format;
    p.appendChild(a);
  }

  function inject() {
    var cfg = window.timepdfConfig;
    if (!cfg) return;
    var url = buildUrl(cfg.url);
    injectContextual(cfg, url);
    injectOtherFormats(cfg, url);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', inject);
  } else {
    inject();
  }
})();
