# Injects the PDF export button into the Spent time view.
# Uses view_layouts_base_html_head (the only reliable hook that fires on every
# page in Redmine 6) and gates rendering to TimelogController#index. Actual
# DOM injection happens client-side in assets/javascripts/timepdf.js, since
# Redmine 6's timelog/index.html.erb no longer calls view_timelog_index_*
# hooks.
module Timepdf
  class Hooks < Redmine::Hook::ViewListener
    def view_layouts_base_html_head(context = {})
      controller = context[:controller]
      return '' unless controller &&
                       controller.controller_name == 'timelog' &&
                       controller.action_name == 'index'

      project = controller.instance_variable_get(:@project)
      return '' unless project &&
                       User.current.allowed_to?(:export_spenttime_pdf, project)

      controller.send(
        :render_to_string,
        partial: 'timepdf/head_inject',
        locals: { project: project }
      )
    end
  end
end
