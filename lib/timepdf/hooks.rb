# View hooks to inject the export link into the Actions menu and the 'Also available in' area.
module Timepdf
  class Hooks < Redmine::Hook::ViewListener
    def view_timelog_index_contextual(context={})
      controller = context[:controller]; project = context[:project]
      return '' unless controller && project && User.current.allowed_to?(:export_spenttime_pdf, project)
      controller.render_to_string(partial: 'timepdf/export_action')
    rescue
      ''
    end

    def view_timelog_index_other_formats(context={})
      controller = context[:controller]; project = context[:project]
      return '' unless controller && project && User.current.allowed_to?(:export_spenttime_pdf, project)
      controller.render_to_string(partial: 'timepdf/export_other')
    rescue
      ''
    end
  end
end
