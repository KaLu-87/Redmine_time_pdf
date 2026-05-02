# Route for the export action (no Rails.application.routes.draw here; Redmine merges plugin routes).
get  'projects/:project_id/timepdf/export',        to: 'timepdf#export',        as: 'timepdf_export_project'
get  'projects/:project_id/timepdf/report_export', to: 'timepdf#report_export', as: 'timepdf_report_export_project'
get  'timepdf/upload_logo', to: 'timepdf#upload_logo_form', as: 'timepdf_upload_logo_form'
post 'timepdf/upload_logo', to: 'timepdf#upload_logo',      as: 'timepdf_upload_logo'
