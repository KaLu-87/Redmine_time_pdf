# Injects the PDF export button into the Spent time view (Details and Report).
# Uses view_layouts_base_html_head (the only reliable hook in Redmine 6) and
# dispatches on the current action and per-tab permission. Actual DOM injection
# happens client-side in assets/javascripts/timepdf.js, since Redmine 6's
# timelog views no longer call view_timelog_index_* hooks.
module Timepdf
  class Hooks < Redmine::Hook::ViewListener
    DETAILS = {
      mode: :details,
      permission: :export_spenttime_pdf
    }.freeze

    REPORT = {
      mode: :report,
      permission: :export_spenttime_report_pdf
    }.freeze

    def view_layouts_base_html_head(context = {})
      controller = context[:controller]
      return '' unless controller && controller.controller_name == 'timelog'

      project = controller.instance_variable_get(:@project)
      return '' unless project

      cfg = case controller.action_name
            when 'index'  then DETAILS
            when 'report' then REPORT
            end
      return '' unless cfg && User.current.allowed_to?(cfg[:permission], project)

      controller.send(
        :render_to_string,
        partial: 'timepdf/head_inject',
        locals: { project: project, mode: cfg[:mode] }
      )
    end
  end
end
