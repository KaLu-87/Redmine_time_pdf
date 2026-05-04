# Registers the plugin and its settings/permissions with Redmine.
require_relative 'lib/timepdf/hooks'

Redmine::Plugin.register :redmine_timepdf do
  name 'Time PDF Export'
  author 'KLu – with AI assistance'
  description 'Export the Spent time list as a formatted PDF using current filters/columns/grouping.'
  version '0.5.4'
  requires_redmine version_or_higher: '6.0.0'

  project_module :timepdf do
    permission :export_spenttime_pdf,        { timepdf: [:export] },        require: :member
    permission :export_spenttime_report_pdf, { timepdf: [:report_export] }, require: :member
  end

  settings default: { 'logo_path' => '' }, partial: 'settings/timepdf_settings'
end
