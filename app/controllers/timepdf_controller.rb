# Controller that renders the PDF for time entries using the user's active filters.
class TimepdfController < ApplicationController
  before_action :find_project, only: [:export, :report_export]
  before_action :authorize,    only: [:export, :report_export]
  before_action :require_admin, only: [:upload_logo_form, :upload_logo]

  MAX_ENTRIES = 2000
  MAX_PERIODS = 24      # Hard cap on report-pivot columns; exceeding it renders a hint page.
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

  # Renders the Report tab (TimelogController#report) as a PDF pivot table.
  # Mirrors Redmine::Helpers::TimeReport: rows = selected criteria,
  # columns = chosen time periods, cells = aggregated hours.
  def report_export
    @query = TimeEntryQuery.build_from_params(params, name: '_')
    @query.project = @project if @project

    criteria = Array(params[:criteria]).reject(&:blank?)
    columns  = params[:columns].presence || 'month'
    @report  = Redmine::Helpers::TimeReport.new(@project, criteria, columns, @query.results_scope)

    Rails.logger.info("[timepdf] report criteria=#{criteria.inspect} columns=#{columns} periods=#{@report.periods.size}")

    pdf = build_report_pdf(@project, @report)
    send_data pdf.render,
              filename: "spent_time_report_#{@project.identifier}_#{Date.today}.pdf",
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

  # Renders the project header (title left, optional logo top-right).
  def draw_pdf_header(doc, project, logo_path)
    header_y = doc.cursor
    doc.text project.name, size: 16, style: :bold
    if logo_path
      begin
        doc.image logo_path, at: [doc.bounds.right - 120, header_y], fit: [100, 40]
        doc.move_cursor_to(header_y - 40) if doc.cursor > (header_y - 40)
      rescue StandardError => e
        Rails.logger.warn("[timepdf] logo load failed: #{e.class}: #{e.message}")
      end
    end
    doc.move_down 8
  end

  def draw_pdf_footer(doc)
    doc.number_pages "<page>/<total>", at: [doc.bounds.right - 50, 0], size: 9
    doc.number_pages "#{l(:timepdf_generated)}: #{Date.today.strftime('%Y-%m-%d')}", at: [0, 0], size: 9
  end

  # Pivot-table PDF for the Report tab. If the period count exceeds MAX_PERIODS,
  # the table is replaced by a hint page so users narrow the date range or pick
  # a coarser unit (month instead of day, etc.).
  def build_report_pdf(project, report)
    require 'prawn'
    require 'prawn/table'

    logo_path = sanitized_logo_path

    Prawn::Document.new(page_size: 'A4', page_layout: :landscape, margin: 36).tap do |doc|
      draw_pdf_header(doc, project, logo_path)

      subtitle = report_subtitle(report)
      if subtitle.present?
        doc.text subtitle, size: 10, style: :italic
        doc.move_down 6
      end

      if report.hours.empty?
        doc.text l(:timepdf_no_entries), style: :italic
      elsif report.periods.size > MAX_PERIODS
        doc.text l(:timepdf_report_too_many_periods, count: report.periods.size, max: MAX_PERIODS),
                 style: :italic, color: 'CC0000'
      else
        draw_report_table(doc, report)
      end

      draw_pdf_footer(doc)
    end
  end

  def draw_report_table(doc, report)
    periods    = report.periods
    crit_count = report.criteria.size

    header_row =
      report.criteria.map { |c| criterion_caption(report, c) } +
      periods.map        { |p| period_caption(p, report.columns) } +
      [l(:timepdf_total)]

    data_rows = build_report_data_rows(report, periods)
    total_row = build_report_total_row(report, periods)

    table_data = [header_row] + data_rows + [total_row]

    last_idx = table_data[0].size - 1
    tbl = doc.make_table(
      table_data,
      header: true,
      row_colors: ['F8F8F8', 'FFFFFF']
    )

    tbl.cells.padding = 4
    tbl.cells.borders = [:bottom]
    tbl.row(0).font_style       = :bold
    tbl.row(0).background_color = 'FFFFFF'
    tbl.row(0).borders          = [:top, :bottom]
    tbl.row(0).border_width     = 1.5
    tbl.row(-1).font_style       = :bold
    tbl.row(-1).background_color = 'D9D9D9'
    tbl.row(-1).borders          = [:top, :bottom]
    tbl.row(-1).border_width     = 1.5

    # Right-align all numeric columns (period columns + total column).
    (crit_count..last_idx).each { |i| tbl.columns(i).align = :right }

    tbl.draw
  end

  # Aggregates report.hours into one row per unique criteria-value tuple.
  def build_report_data_rows(report, periods)
    return [] if report.criteria.empty?

    grouped = report.hours.group_by { |h| report.criteria.map { |c| h[c] } }
    grouped.sort_by { |key, _| key.map { |v| criterion_sort_key(v) } }.map do |values, entries|
      per_period = entries.group_by { |h| h['period'] }
                          .transform_values { |hs| hs.sum { |h| h['hours'].to_f } }
      row_total = entries.sum { |h| h['hours'].to_f }

      label_cells  = values.zip(report.criteria).map { |v, c| format_criterion_value(report, c, v) }
      period_cells = periods.map { |p| per_period[p] ? sprintf('%.2f', per_period[p]) : '' }
      [*label_cells, *period_cells, sprintf('%.2f', row_total)]
    end
  end

  # Bottom totals: per-period sums across all rows + grand total.
  def build_report_total_row(report, periods)
    per_period  = report.hours.group_by { |h| h['period'] }
                              .transform_values { |hs| hs.sum { |h| h['hours'].to_f } }
    grand_total = report.hours.sum { |h| h['hours'].to_f }

    leading = [l(:timepdf_total)] + ([''] * [report.criteria.size - 1, 0].max)
    leading + periods.map { |p| sprintf('%.2f', per_period[p] || 0) } + [sprintf('%.2f', grand_total)]
  end

  def criterion_sort_key(value)
    value.to_s
  end

  def criterion_caption(report, criterion)
    cfg = report.available_criteria[criterion]
    cfg && cfg[:label] ? l(cfg[:label]) : criterion.to_s.humanize
  end

  # Resolves a criterion's raw value (often an ID) into a human label via its klass.
  def format_criterion_value(report, criterion, value)
    return "[#{l(:label_none)}]" if value.blank?
    cfg = report.available_criteria[criterion]
    return value.to_s unless cfg

    klass = cfg[:klass]
    return value.to_s unless klass

    obj = klass.find_by(id: value)
    return value.to_s unless obj

    case obj
    when Issue then "##{obj.id}: #{obj.subject}"
    else obj.to_s
    end
  rescue StandardError
    value.to_s
  end

  def period_caption(period, columns)
    case columns
    when 'month'
      year = period[0, 4]
      month = period[5, 2].to_i
      month_name = Date::ABBR_MONTHNAMES[month] || month.to_s
      "#{month_name} #{year}"
    else
      period.to_s
    end
  end

  def report_subtitle(report)
    parts = []
    parts << report.criteria.map { |c| criterion_caption(report, c) }.join(' / ') if report.criteria.any?
    if report.periods.any?
      first = period_caption(report.periods.first, report.columns)
      last  = period_caption(report.periods.last,  report.columns)
      parts << (first == last ? first : "#{first} – #{last}")
    end
    parts.join(' • ')
  end
end
