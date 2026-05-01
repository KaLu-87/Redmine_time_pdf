# Route for the export action (no Rails.application.routes.draw here; Redmine merges plugin routes).
get 'projects/:project_id/timepdf/export', to: 'timepdf#export', as: 'timepdf_export_project'
