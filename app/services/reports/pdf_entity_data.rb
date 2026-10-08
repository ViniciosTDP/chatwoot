class Reports::PdfEntityData < Reports::PdfMetrics
  def build
    raise CustomExceptions::ReportPdf, 'too_large' if scope.count > ReportExport::MAX_ROWS

    { metrics: [], headers: [Reports::PdfText.t("report_pdf.types.#{export.report_type}")] + SUMMARY_METRICS.map { |key| metric_label(key) },
      rows: reports.map { |report| row(report) }, charts: [chart] }
  end

  private

  def scope
    { 'agent' => account.users, 'inbox' => account.inboxes, 'team' => account.teams, 'label' => account.labels }.fetch(export.report_type)
  end

  def reports
    @reports ||= "V2::Reports::#{export.report_type.classify}SummaryBuilder".constantize.new(account: account, params: params).build
  end

  def entities
    @entities ||= scope.index_by(&:id)
  end

  def entity_name(report)
    entity = entities.fetch(report[:id])
    export.report_type == 'label' ? entity.title : entity.name
  end

  def row(report)
    [entity_name(report)] + SUMMARY_METRICS.map { |key| format_value(key, report[key.to_sym]) }
  end

  def chart
    top = reports.sort_by { |report| [-report[:conversations_count].to_i, report[:id]] }.first(10)
    { type: :bar, labels: top.map { |report| entity_name(report) }, unit: :count, title: Reports::PdfText.t('report_pdf.top_ten'),
      series: %w[conversations_count resolved_conversations_count].map do |key|
        { name: metric_label(key), values: top.map { |report| report[key.to_sym] } }
      end }
  end
end
