# Time PDF Export Plugin (v0.5.3)

## Overview
The **Time PDF Export** plugin for Redmine allows exporting the *Spent time*
view of any project into a clean, printable **PDF report** — both the
**Details** tab (per-entry list) and the **Report** tab (pivot table).

It respects all active filters, groupings, columns, criteria and time periods
in Redmine and is designed for clear, professional time tracking summaries.

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
- Details export limited to 2,000 entries; Report export limited to 12
  periods (one year of months); a hint page is rendered if either limit is
  exceeded

---

## Compatibility
- Tested with **Redmine 6.0.x**
- Requires **Ruby 3.3+**
- Dependencies: `prawn`, `prawn-table` (installed via `bundle install`)

---

## Development Notes

- Written in Ruby on Rails using Redmine's plugin API.
- PDF generation by Prawn and Prawn-Table.
- Integrates via the `view_layouts_base_html_head` hook on
  `TimelogController#index` and `TimelogController#report`; the export button
  is injected client-side (`assets/javascripts/timepdf.js`) because Redmine 6
  no longer exposes `view_timelog_index_*` hooks.
- Fully permission-controlled through Redmine roles.
- Compatible with Apache + Passenger or Puma deployments.

---

## Configuration

### 1. Set logo (optional)
Go to:
    Administration → Plugins → Time PDF Export → Configure

**Option A – Upload via browser (recommended for first install):**
Click the "Upload Logo" link next to the logo path field.
Select a PNG or JPG file (max. 2 MB). The path is set automatically and
the file is stored under `<plugin_dir>/files/`.

**Option B – Set path manually (recommended for permanent setups):**
Enter the absolute path to a PNG/JPG file on the server.
The file may live anywhere readable by the webserver user, e.g.:

    /var/www/html/redmine/themes/<your_theme>/images/logo.png
    /var/www/html/redmine/plugins/redmine_timepdf/files/logo.png

Make sure the file is readable by the webserver user (e.g., `www-data`).

> **Note:** Files inside `<plugin_dir>/files/` are removed when the plugin is
> replaced during an update. For a permanent logo, put it in your theme
> directory or another location outside `plugins/` and point `logo_path`
> there.

### 2. Set permissions
Go to:
    Administration → Roles and permissions → Projects → Time PDF Export
Enable one or both permissions:

    Export spent time PDF          (Details tab)
    Export spent time report PDF   (Report tab)

The project module **Time PDF Export** must also be enabled in each project
where the buttons should appear (Project settings → Modules).

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

> A filter must be applied before exporting Details. If no entries match the
> selected filters, the PDF displays an informational message instead of an
> empty document. Reports with more than 12 periods are not rendered as a
> table — narrow the date range or pick a coarser unit (e.g. month instead
> of day).

---

## Installation

Perform all commands as **root**.

1. **Drop the plugin into the Redmine plugins directory.** Either upload
   a release ZIP via SFTP and unpack it, or pull from Git:

       cd /var/www/html/redmine/plugins
       git clone <repository-url> redmine_timepdf
       # or:
       # unzip /tmp/redmine_timepdf.zip -d .
       # mv redmine_timepdf-* redmine_timepdf

       chown -R www-data:www-data redmine_timepdf

2. **Install Ruby dependencies (Prawn + Prawn-Table):**

       cd /var/www/html/redmine
       su -s /bin/bash www-data -c "bundle install"

3. **Clear caches and restart Apache:**

       rm -rf tmp/cache/*
       systemctl restart apache2

### Verify installation
In Redmine, go to:

    Administration → Plugins

You should see: **Time PDF Export (v0.5.3)**

---

## Update

Plugin settings (logo path, permissions) live in the database and survive an
update; only the file tree is replaced.

Perform all commands as **root**.

1. **Move the previous version OUT of the plugins directory.** Redmine loads
   every subdirectory under `plugins/` as a plugin, so a backup left next to
   the new version registers duplicate routes and prevents Redmine from
   booting.

       cd /var/www/html/redmine/plugins
       mv redmine_timepdf /root/redmine_timepdf.backup_$(date +%Y%m%d)

2. **Drop in the new version** (Git pull or fresh ZIP):

       git clone <repository-url> redmine_timepdf
       # or replace via ZIP as in the install step
       chown -R www-data:www-data redmine_timepdf

3. **If the previous version had a browser-uploaded logo,** copy it back
   (the `files/` folder is wiped together with the old plugin tree):

       cp -a /root/redmine_timepdf.backup_*/files/. \
             /var/www/html/redmine/plugins/redmine_timepdf/files/ 2>/dev/null || true

   Skipping this is fine if the logo path points outside the plugin
   directory (recommended — see Configuration → Option B).

4. **Clear the cache and the precompiled plugin assets, then restart:**

       cd /var/www/html/redmine
       rm -rf tmp/cache/*
       rm -rf public/plugin_assets/redmine_timepdf
       systemctl restart apache2

   Removing `public/plugin_assets/redmine_timepdf` forces Redmine to copy
   the updated `timepdf.js` over on next boot. Without this step, the
   browser may keep loading the previous fingerprint.

5. **Hard-refresh the browser** (Ctrl+F5) so the new JavaScript is loaded.

---

## Uninstallation

Perform all commands as **root**.

1. Remove the plugin tree:

       cd /var/www/html/redmine/plugins
       rm -rf redmine_timepdf

2. Remove the precompiled assets:

       cd /var/www/html/redmine
       rm -rf public/plugin_assets/redmine_timepdf

3. Clear the cache and restart Redmine:

       rm -rf tmp/cache/*
       systemctl restart apache2

The plugin's settings entry in the database remains. To remove it as well,
run from the Redmine root:

    su -s /bin/bash www-data -c "RAILS_ENV=production rails runner \
        \"Setting.where(name: 'plugin_redmine_timepdf').destroy_all\""

---

## Author
KLu – with AI assistance
(c) 2025 – MIT License
Optimized for maintainability and clarity.
