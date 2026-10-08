class Reports::PdfMetrics
  attr_reader :export, :account, :params

  METRICS = %w[conversations_count incoming_messages_count outgoing_messages_count avg_first_response_time
               avg_resolution_time resolutions_count reply_time].freeze
  SUMMARY_METRICS = %w[conversations_count avg_first_response_time avg_resolution_time avg_reply_time resolved_conversations_count].freeze
  LABEL_ALIASES = { 'resolved_conversations_count' => 'resolution_count', 'resolutions_count' => 'resolution_count',
                    'reply_time' => 'avg_customer_waiting_time', 'avg_reply_time' => 'avg_customer_waiting_time' }.freeze

  def initialize(export)
    @export = export
    @account = export.account
    @params = Reports::PdfFilters.new(export).builder_params
  end

  def format_value(key, value)
    return '—' if value.nil?
    return Reports::PdfText.time(value.to_f) if key.include?('time')

    value.to_i.to_s
  end

  def metric_label(key)
    I18n.t("reports.conversation_csv.#{LABEL_ALIASES.fetch(key, key)}")
  end

  def date_label(timestamp)
    Time.at(timestamp).getlocal((params.fetch(:timezone_offset, 0).to_f * 3600).to_i).strftime('%d/%m/%Y')
  end
end
