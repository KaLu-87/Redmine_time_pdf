# Controller that renders the PDF for time entries using the user's active filters.
class TimepdfController < ApplicationController
  before_action :find_project, only: [:export]
  before_action :authorize,    only: [:export]  # checks :export_spenttime_pdf via plugin permission
  before_action :require_admin, only: [:upload_logo_form, :upload_logo]

  MAX_ENTRIES = 2000
  HOURS_WIDTH = 120
  COLUMN_WIDTHS = {
    spent_on: 55,
    user:     80,
    author:   80,
    activity: 75,
    issue:    110,
    project:  110,
  }.freeze

  def upload_logo_form
    @current_path = (Setting.plugin_redmine_timepdf['logo_path'] || '').to_s
  end

  def upload_logo
    uploaded = params[:logo_file]

    unless uploaded.is_a?(ActionDispatch::Http::UploadedFile)
      flash[:error] = l(:timepdf_upload_no_file)
      redirect_to timepdf_upload_logo_form_path and return
    end

    ext = File.extname(uploaded.original_filename).downcase
    unless %w[.png .jpg .jpeg].include?(ext)
      flash[:error] = l(:timepdf_upload_invalid_type)
      redirect_to timepdf_upload_logo_form_path and return
    end

    if uploaded.size > 2.megabytes
      flash[:error] = l(:timepdf_upload_too_large)
      redirect_to timepdf_upload_logo_form_path and return
    end

    plugin_dir = Redmine::Plugin.find(:redmine_timepdf).directory
    files_dir  = File.join(plugin_dir, 'files')
    FileUtils.mkdir_p(files_dir)
    dest = File.join(files_dir, "logo#{ext}")
    FileUtils.cp(uploaded.tempfile.path, dest)

    settings = Setting.plugin_redmine_timepdf.dup
    settings['logo_path'] = dest
    Setting.plugin_redmine_timepdf = settings

    flash[:notice] = l(:timepdf_upload_success)
    redirect_to plugin_settings_path(:redmine_timepdf)
  end

  def export
    Rails.logger.info("[timepdf] params=#{params.to_unsafe_h.inspect}")
    @query = TimeEntryQuery.build_from_params(params, name: '_')
    @query.project = @project if @project

    scope   = @query.results_scope.includes(:user, :issue, :activity, :project)
    entries = scope.limit(MAX_ENTRIES + 1).to_a
    truncated = entries.size > MAX_ENTRIES
    entries   = entries.first(MAX_ENTRIES) if truncated
    Rails.logger.warn("[timepdf] result truncated to #{MAX_ENTRIES}") if truncated
    Rails.logger.info("[timepdf] entries=#{entries.size}")

    columns = @query.inline_columns.reject { |c| c.name == :hours }
    if columns.blank?
      default_names = [:spent_on, :user, :issue, :activity, :comments]
      columns = @query.available_columns.select { |c| default_names.include?(c.name) }
    end
    Rails.logger.info("[timepdf] columns=#{columns.map(&:name)}")

    group_by = @query.group_by
    groups = if group_by.present?
               entries.group_by { |e| @query.group_by_column.value(e) }
             else
               { nil => entries }
             end

    pdf = build_pdf(@project, columns, groups, group_by, entries.empty?, truncated)
    send_data pdf.render,
              filename: "spent_time_#{@project.identifier}_#{Date.today}.pdf",
              type: 'application/pdf',
              disposition: 'inline'
  end

  private

  def find_project
    @project = Project.find(params[:project_id])
  end

  # Assigns sensible column widths based on column type.
  # Known columns get fixed widths; any remaining width goes to unknown columns (e.g. comments).
  def column_widths_for(columns, total_width)
    widths     = columns.each_with_index.with_object({}) do |(col, i), h|
      h[i] = COLUMN_WIDTHS[col.name] if COLUMN_WIDTHS.key?(col.name)
    end
    assigned   = widths.values.sum + HOURS_WIDTH
    free_count = columns.size - widths.size
    fallback   = free_count > 0 ? [(total_width - assigned) / free_count, 40].max.floor : 0
    columns.each_index { |i| widths[i] ||= fallback }
    widths[columns.size] = HOURS_WIDTH
    widths
  end

  # Returns the real, validated logo path or nil if missing/outside the plugin directory.
  def sanitized_logo_path
    raw = (Setting.plugin_redmine_timepdf['logo_path'] || '').to_s.strip
    return nil if raw.blank?

    unless File.file?(raw) && File.readable?(raw)
      Rails.logger.warn("[timepdf] logo path not a readable file: #{raw}")
      return nil
    end

    unless %w[.png .jpg .jpeg].include?(File.extname(raw).downcase)
      Rails.logger.warn("[timepdf] logo path has unsupported extension: #{raw}")
      return nil
    end

    raw
  rescue Errno::ENOENT, Errno::EACCES => e
    Rails.logger.warn("[timepdf] logo path not accessible: #{e.message}")
    nil
  end

  # Landscape A4 PDF: no vertical rules, zebra rows, bold header,
  # widened right-aligned "Hours" column, highlighted summary rows,
  # 14pt spacing after each summary, and 28pt spacing before each next group header.
  def build_pdf(project, columns, groups, group_by, no_data, truncated = false)
    require 'prawn'
    require 'prawn/table'

    logo_path = sanitized_logo_path

    Prawn::Document.new(page_size: 'A4', page_layout: :landscape, margin: 36).tap do |doc|
      # Header with optional logo at top-right.
      header_y = doc.cursor
      doc.text project.name, size: 16, style: :bold
      if logo_path
        begin
          doc.image logo_path, at: [doc.bounds.right - 120, header_y], fit: [100, 40]
          # If the logo is taller than the project name text, push the cursor down to clear it.
          doc.move_cursor_to(header_y - 40) if doc.cursor > (header_y - 40)
        rescue StandardError => e
          Rails.logger.warn("[timepdf] logo load failed: #{e.class}: #{e.message}")
        end
      end
      doc.move_down 8

      if no_data
        doc.text l(:timepdf_no_entries), style: :italic
      else
        if truncated
          doc.text l(:timepdf_truncated, count: MAX_ENTRIES), style: :italic, color: 'CC0000'
          doc.move_down 6
        end
        groups.each_with_index do |(gval, rows), idx|
          next if rows.empty?

          # Add 28pt spacing BEFORE every group except the first one
          if idx > 0
            doc.move_down 28
          end

          if group_by.present?
            title = @query.group_by_column.caption
            doc.text "#{title}: #{gval}", style: :bold
            doc.move_down 4
          end

          header = columns.map(&:caption) + [l(:timepdf_hours)]
          table_data = [header]

          rows.each do |t|
            line = columns.map { |c| (c.value(t) || '').to_s }
            line << sprintf('%.2f', t.hours.to_f)
            table_data << line
          end

          # Append per-group summary row.
          group_sum = rows.sum { |r| r.hours.to_f }
          table_data << ([''] * (header.size - 1) + ["#{l(:timepdf_total)}: #{sprintf('%.2f', group_sum)}"])

          last_idx = header.size - 1
          tbl = doc.make_table(
            table_data,
            header: true,
            row_colors: ['F8F8F8', 'FFFFFF'],
            column_widths: column_widths_for(columns, doc.bounds.width)
          )

          tbl.cells.padding = 4
          tbl.cells.borders = [:bottom]  # horizontal lines only
          tbl.row(0).font_style = :bold
          tbl.row(0).background_color = 'FFFFFF'
          tbl.row(0).borders = [:top, :bottom]
          tbl.row(0).border_width = 1.5
          tbl.row(-1).font_style = :bold
          tbl.row(-1).background_color = 'D9D9D9'
          tbl.row(-1).borders = [:top, :bottom]
          tbl.row(-1).border_width = 1.5
          tbl.columns(last_idx).align = :right

          # Draw and add second bottom line to simulate double border, then 14pt spacing after summary.
          tbl.draw
          bottom_y = doc.cursor
          doc.save_graphics_state
          doc.move_cursor_to(bottom_y - 2)
          doc.stroke_color '000000'
          doc.line_width = 0.75
          doc.stroke_horizontal_rule
          doc.restore_graphics_state

          doc.move_down 14  # 14pt after each group's summary
        end

        if group_by.present? && groups.size > 1
          grand_total = groups.values.flatten.sum { |r| r.hours.to_f }
          col_count   = columns.size + 1
          grand_row   = [''] * (col_count - 1) + ["#{l(:timepdf_grand_total)}: #{sprintf('%.2f', grand_total)}"]

          tbl = doc.make_table(
            [grand_row],
            column_widths: column_widths_for(columns, doc.bounds.width)
          )
          tbl.cells.padding       = 4
          tbl.cells.borders       = [:top, :bottom]
          tbl.cells.border_width  = 1.5
          tbl.cells.font_style    = :bold
          tbl.cells.background_color = 'B0B0B0'
          tbl.columns(col_count - 1).align = :right
          tbl.draw
        end
      end

      # Footer
      doc.number_pages "<page>/<total>", at: [doc.bounds.right - 50, 0], size: 9
      doc.number_pages "#{l(:timepdf_generated)}: #{Date.today.strftime('%Y-%m-%d')}", at: [0, 0], size: 9
    end
  end
end
