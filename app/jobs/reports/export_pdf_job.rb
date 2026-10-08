class Reports::ExportPdfJob < ApplicationJob
  queue_as :report_exports

  def perform(export_id)
    export = ReportExport.find(export_id)
    return if export.completed? || export.expires_at <= Time.current
    raise CustomExceptions::ReportPdf, 'access_denied' unless export.permitted?

    Reports::PdfFilters.new(export).validate!
    export.update!(status: :processing, error_code: nil, processed_at: Time.current)
    I18n.with_locale(:pt_BR) { generate(export) }
  rescue CustomExceptions::ReportPdf => e
    export&.update!(status: :failed, error_code: e.code)
  rescue StandardError => e
    export&.update!(status: :failed, error_code: 'generation_failed')
    Rails.logger.error "Report PDF failed export_id=#{export_id} error_class=#{e.class.name}"
  end

  private

  def generate(export)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    data = Reports::PdfData.new(export).build
    html = Reports::PdfHtml.new(export, data).render
    pdf = Reports::PdfClient.new.render(html, export)
    raise CustomExceptions::ReportPdf, 'access_denied' unless export.permitted?

    export.document.attach(io: StringIO.new(pdf), filename: "#{export.report_type}-report-#{export.id}.pdf", content_type: 'application/pdf')
    export.update!(status: :completed)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    Rails.logger.info "Report PDF completed export_id=#{export.id} elapsed=#{elapsed.round(2)} bytes=#{pdf.bytesize}"
  end
end
