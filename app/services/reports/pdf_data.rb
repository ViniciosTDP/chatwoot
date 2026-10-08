class Reports::PdfData
  def initialize(export)
    @export = export
  end

  def build
    kind = @export.report_type
    adapter = if kind == 'sla'
                Reports::SlaPdfData
              elsif kind == 'csat'
                Reports::CsatPdfData
              elsif kind == 'conversation' || @export.filters['id'].present?
                Reports::PdfTimeseriesData
              else
                Reports::PdfEntityData
              end
    result = adapter.new(@export).build
    raise CustomExceptions::ReportPdf, 'too_large' if result[:rows].length > ReportExport::MAX_ROWS

    result.merge(filters: Reports::PdfFilterPresenter.new(@export).build)
  end
end
