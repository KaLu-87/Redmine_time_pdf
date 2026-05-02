# Time PDF Export Plugin (v0.5.0)

## Overview
The **Time PDF Export** plugin for Redmine allows exporting the *Spent time* view of any project into a clean, printable **PDF report**.

It respects all active filters, groupings, and visible columns in Redmine and is designed for clear, professional time tracking summaries.

### Key Features
- Exports the current "Spent time" view as a PDF (Details tab)
- Exports the Report tab as a pivot-table PDF (criteria x periods)
- Separate permissions for Details and Report exports
- Includes project title and optional logo in the header
- Logo upload via the admin interface (no manual file copying required)
- Logo can live in the plugin directory, a theme directory, or any
  readable location on the server
- Groups and summarizes time entries with per-group subtotals
- Grand total row across all groups when grouping is active
- Decimal-based hours (e.g., 7.50 instead of 7:30)
- Clean, borderless layout (no vertical lines)
- Bold table header with thicker lines
- Highlighted summary rows (dark gray), grand total row (medium gray)
- Zebra-striped rows for readability
- Landscape orientation for optimal space
- Double bottom line under each summary row
- 14pt spacing after every summary, 28pt before each new group
- Opens PDF in a new browser tab
- Multilingual: English and German included
- Details export limited to 2,000 entries; Report export limited to 24
  periods; warning shown in PDF if exceeded

---

## Compatibility
- Tested with **Redmine 6.0.x**
- Requires **Ruby 3.3+**
- Dependencies: `prawn`, `prawn-table` (installed automatically)

---

## Development Notes

- Written in Ruby on Rails using Redmine's plugin API.
- PDF generation by Prawn and Prawn-Table.
- Integrates via the view_layouts_base_html_head hook on TimelogController#index;
  the export button is injected client-side (assets/javascripts/timepdf.js)
  because Redmine 6 no longer exposes view_timelog_index_* hooks.
- Fully permission-controlled through Redmine roles.
- Compatible with Apache + Passenger or Puma deployments.

---

## Configuration

### 1. Set logo (optional)
Go to:
    Administration → Plugins → Time PDF Export → Configure

**Option A – Upload via browser (recommended):**
Click the "Upload Logo" link next to the logo path field.
Select a PNG or JPG file (max. 2 MB). The path is set automatically.

**Option B – Set path manually:**
Enter the absolute path to a PNG/JPG file on the server.
The file may live anywhere readable by the webserver user, e.g.:
    /var/www/html/redmine/plugins/redmine_timepdf/files/logo.png
    /var/www/html/redmine/themes/<your_theme>/images/logo.png

Make sure the file is readable by the webserver user (e.g., www-data).

### 2. Set permissions
Go to:
    Administration → Roles and permissions → Projects → Time PDF Export
Enable one or both permissions:
    Export spent time PDF          (Details tab)
    Export spent time report PDF   (Report tab)

---

## Usage

### Details tab
1. Open a project → Spent time → Details.
2. Apply filters, columns, or groupings as desired.
3. Export via the icon button in the contextual area or the link next
   to "Atom | CSV" at the bottom of the page.
4. The PDF opens in a new browser tab.

### Report tab
1. Open a project → Spent time → Report.
2. Choose criteria (up to 3) and a time unit (year/month/week/day).
3. Export via the icon button in the contextual area or the link next
   to the format links at the bottom of the page.
4. The PDF opens in a new browser tab.

Note: A filter must be applied before exporting Details. If no entries
match the selected filters, the PDF displays an informational message
instead of an empty document. Reports with more than 24 periods are
not rendered as a table — narrow the date range or pick a coarser unit.

---

## Installation

Perform all commands as **root**.

#1. **Upload plugin ZIP file**
   ```bash
   .../redmine/plugins/redmine_timepdf-0.4.0.zip

#2. **Unzip into the Redmine plugins directory
   cd /var/www/html/redmine/plugins
   unzip redmine_timepdf-0.4.0.zip
   [ -d redmine_timepdf_040 ] && mv redmine_timepdf_040 redmine_timepdf
   chown -R www-data:www-data redmine_timepdf

#3. **Install dependencies
    cd /var/www/html/redmine
    su -s /bin/bash www-data -c "bundle install"

#4. **Clear cache and restart Apache
    rm -rf tmp/cache/*
    systemctl restart apache2

---

## Verify installation
    In Redmine:
    Administration → Plugins
    You should see: Time PDF Export (v0.4.0)

---

## Uninstallation

Perform all commands as **root**.

#1. Remove the plugin:
    cd /var/www/html/redmine/plugins
    rm -rf redmine_timepdf

#2. Clear cache and restart Redmine:
    cd /var/www/html/redmine
    rm -rf tmp/cache/*
    systemctl restart apache2

---

## Author
KLu – with AI assistance
(c) 2025 – MIT License
Optimized for maintainability and clarity.
