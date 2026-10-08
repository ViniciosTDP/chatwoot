class Reports::PdfTimeseriesData < Reports::PdfMetrics
  CHART_GROUPS = [%w[conversations_count resolutions_count], %w[incoming_messages_count outgoing_messages_count],
                  %w[avg_first_response_time avg_resolution_time reply_time]].freeze

  def build
    summary = V2::Reports::Conversations::MetricBuilder.new(account, builder_params).summary
    { metrics: keys.map { |key| [metric_label(key), format_value(key, summary[key.to_sym])] },
      headers: [Reports::PdfText.t('report_pdf.interval')] + keys.map { |key| metric_label(key) }, rows: rows, charts: charts }
  end

  private

  def keys
    @keys ||= export.report_type == 'agent' ? METRICS - ['incoming_messages_count'] : METRICS
  end

  def builder_params
    params.merge(type: export.report_type == 'conversation' ? 'account' : export.report_type)
  end

  def indexes
    @indexes ||= keys.index_with do |key|
      points = V2::Reports::Conversations::ReportBuilder.new(account, builder_params.merge(metric: key)).timeseries
      points.index_by { |point| point[:timestamp] }
    end
  end

  def timestamps
    @timestamps ||= indexes.values.flat_map(&:keys).uniq.sort
  end

  def rows
    raise CustomExceptions::ReportPdf, 'too_large' if timestamps.length > ReportExport::MAX_ROWS

    timestamps.map do |timestamp|
      [date_label(timestamp)] + keys.map { |key| format_value(key, indexes[key].dig(timestamp, :value)) }
    end
  end

  def charts
    CHART_GROUPS.map do |group|
      { type: :line, labels: timestamps.map { |timestamp| date_label(timestamp) },
        unit: group.first.include?('time') ? :time : :count, series: chart_series(group & keys) }
    end
  end

  def chart_series(selected_keys)
    selected_keys.map { |key| { name: metric_label(key), values: timestamps.map { |timestamp| indexes[key].dig(timestamp, :value) } } }
  end
end
