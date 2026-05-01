# Retry creation of README_TimePDF_0.3.8.txt
readme_content = """# Time PDF Export Plugin (v0.3.8)

## Overview
The **Time PDF Export** plugin for Redmine allows exporting the *Spent time* view of any project into a clean, printable **PDF report**.

It respects all active filters, groupings, and visible columns in Redmine and is designed for clear, professional time tracking summaries.

### Key Features
- Exports the current “Spent time” view as a PDF
- Includes project title and optional logo in the header
- Groups and summarizes time entries
- Decimal-based hours (e.g., 7.50 instead of 7:30)
- Clean, borderless layout (no vertical lines)
- Bold table header with thicker lines
- Highlighted summary rows (dark gray)
- Zebra-striped rows for readability
- Landscape orientation for optimal space
- Double bottom line under each summary row
- 14pt spacing after every summary
- 28pt spacing before each new group
- Opens PDF in a new browser tab

---

## Compatibility
- Tested with **Redmine 6.0.x**
- Requires **Ruby 3.3+**
- Dependencies: `prawn`, `prawn-table` (installed automatically)

---

## Development Notes

- Written in Ruby on Rails using Redmine’s plugin API.
- PDF generation by Prawn and Prawn-Table.
- Integrates via Redmine hooks:
    - view_timelog_index_contextual
    - view_timelog_index_other_formats
- Adds dynamic PDF link via small JS script.
- Fully permission-controlled through Redmine roles.
- Compatible with Apache + Passenger or Puma deployments.

---

## Configuration
1. Set logo path (optional)
- Go to:
- Administration → Plugins → Time PDF Export → Configure

- Example path:
    /var/www/html/redmine/plugins/redmine_timepdf/files/logo.png

- Make sure the file is readable by the webserver user (e.g., www-data).

2. Set permissions
- Go to:
    Administration → Roles and permissions → Projects → Time PDF Export
- Enable the permission:
    Export spent time PDF

---

## Usage
1. Open a project → Spent time tab.
2. Apply filters, columns, or groupings as desired.
3. Export via:
    - The Actions (⋯) menu → Export PDF, or
    - The link next to “Atom | CSV” at the bottom of the page.
4. The PDF opens in a new browser tab.

---

## Known Issues

1.  The export function only works effectively if a filter has been applied beforehand. 
    If no filter is applied beforehand, only the first row is exported.
2.  Accumulating the distance traveled can also lead to incorrect behavior. 
    This behavior has not yet been thoroughly investigated.

---

## Installation

Perform all commands as **root**.

#1. **Upload plugin ZIP file**
   ```bash
   .../redmine/plugins/redmine_timepdf-0.3.8.zip

#2. **Unzip into the Redmine plugins directory
   cd /var/www/html/redmine/plugins
   unzip redmine_timepdf-0.3.8.zip
   [ -d redmine_timepdf_038 ] && mv redmine_timepdf_038 redmine_timepdf
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
    You should see: Time PDF Export (v0.3.8)

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