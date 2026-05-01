# Controller that renders the PDF for time entries using the user's active filters.
class TimepdfController < ApplicationController
  before_action :find_project
  before_action :authorize  # checks :export_spenttime_pdf via plugin permission
  helper :timelog
  include TimelogHelper

  def export
    Rails.logger.info("[timepdf] params=#{params.to_unsafe_h.inspect}")
    @query = TimeEntryQuery.build_from_params(params, name: '_')
    @query.project = @project if @project

    scope = @query.results_scope.includes(:user, :issue, :activity, :project)
    entries = scope.to_a
    Rails.logger.info("[timepdf] initial entries=#{entries.size}")

    if entries.empty?
      from = Date.today.beginning_of_month
      to   = Date.today.end_of_month
      scope = TimeEntry.visible.where(project_id: @project.id, spent_on: from..to)
                        .includes(:user, :issue, :activity, :project)
      entries = scope.to_a
      Rails.logger.info("[timepdf] fallback entries=#{entries.size} (#{from}..#{to})")
    end

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

    pdf = build_pdf(@project, columns, groups, group_by, entries.empty?)
    send_data pdf.render,
              filename: "spent_time_#{@project.identifier}_#{Date.today}.pdf",
              type: 'application/pdf',
              disposition: 'inline'
  end

  private

  def find_project
    @project = Project.find(params[:project_id])
  end

  # Landscape A4 PDF: no vertical rules, zebra rows, bold header,
  # widened right-aligned "Hours" column, highlighted summary rows,
  # 14pt spacing after each summary, and 28pt spacing before each next group header.
  def build_pdf(project, columns, groups, group_by, no_data)
    require 'prawn'
    require 'prawn/table'

    logo_path = (Setting.plugin_redmine_timepdf['logo_path'] || '').to_s

    Prawn::Document.new(page_size: 'A4', page_layout: :landscape, margin: 36).tap do |doc|
      # Header with optional logo at top-right.
      header_y = doc.cursor
      doc.text project.name, size: 16, style: :bold
      if logo_path.present? && File.exist?(logo_path)
        begin
          doc.image logo_path, at: [doc.bounds.right - 120, header_y + 16], width: 100
        rescue => e
          Rails.logger.warn("[timepdf] logo load failed: #{e.class}: #{e.message}")
        end
      else
        Rails.logger.info("[timepdf] logo missing or unreadable: #{logo_path}")
      end
      doc.move_down 8

      if no_data
        doc.text "No time entries for the selected filter period.", style: :italic
      else
        group_keys = groups.keys
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

          header = columns.map(&:caption) + ['Hours']
          table_data = [header]

          rows.each do |t|
            line = columns.map { |c| (c.value(t) || '').to_s }
            line << sprintf('%.2f', t.hours.to_f)
            table_data << line
          end

          # Append per-group summary row.
          group_sum = rows.sum { |r| r.hours.to_f }
          table_data << ([''] * (header.size - 1) + ["Total: #{sprintf('%.2f', group_sum)}"])

          last_idx = header.size - 1
          tbl = doc.make_table(
            table_data,
            header: true,
            width: doc.bounds.width,
            row_colors: ['F8F8F8', 'FFFFFF'],
            column_widths: { last_idx => 120 }
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
      end

      # Footer
      doc.number_pages "<page>/<total>", at: [doc.bounds.right - 50, 0], size: 9
      doc.number_pages "Generated: #{Date.today.strftime('%Y-%m-%d')}", at: [0, 0], size: 9
    end
  end
end
