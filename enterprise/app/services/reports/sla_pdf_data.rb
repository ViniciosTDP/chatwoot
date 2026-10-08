class Reports::SlaPdfData
  include DateRangeHelper
  attr_reader :account, :params

  def initialize(export)
    @account = export.account
    @params = Reports::PdfFilters.new(export).builder_params
  end

  def build
    raise CustomExceptions::ReportPdf, 'too_large' if missed > ReportExport::MAX_ROWS

    { metrics: metrics, headers: headers, rows: rows, charts: [chart] }
  end

  private

  def query
    @query ||= account.applied_slas.with_sla_applicable_conversation.filter_by_date_range(range)
                      .filter_by_inbox_id(params[:inbox_id]).filter_by_team_id(params[:team_id])
                      .filter_by_sla_policy_id(params[:sla_policy_id]).filter_by_label_list(params[:label_list])
                      .filter_by_assigned_agent_id(params[:assigned_agent_id])
  end

  def total
    @total ||= query.count
  end

  def missed
    @missed ||= query.missed.count
  end

  def metrics
    hit_rate = Reports::PdfText.percent(total.zero? ? 100 : (total - missed) * 100.0 / total)
    [[Reports::PdfText.t('report_pdf.sla_total'), total], [Reports::PdfText.t('report_pdf.sla_missed'), missed],
     [Reports::PdfText.t('report_pdf.sla_hit_rate'), hit_rate]]
  end

  def headers
    %w[conversation_id sla_policy_breached assignee team inbox labels conversation_link breached_events].map do |key|
      I18n.t("reports.sla_csv.#{key}")
    end
  end

  def rows
    query.missed.includes(:sla_policy, :sla_events, conversation: [:assignee, :team, :inbox]).order(:id).map { |sla| row(sla) }
  end

  def chart
    { type: :bar, unit: :count, labels: [Reports::PdfText.t('report_pdf.sla_without_misses'), Reports::PdfText.t('report_pdf.sla_missed')],
      series: [{ name: Reports::PdfText.t('report_pdf.sla_total'), values: [total - missed, missed] }] }
  end

  def row(sla)
    conversation = sla.conversation
    [conversation.display_id, sla.sla_policy.name, conversation.assignee&.name, conversation.team&.name,
     conversation.inbox&.name, conversation.cached_label_list, conversation_link(conversation), breached_events(sla)]
  end

  def breached_events(sla)
    sla.sla_events.map { |event| Reports::PdfText.t("report_pdf.sla_events.#{event.event_type}") }.join(', ')
  end

  def conversation_link(conversation)
    { text: "##{conversation.display_id}", href: Rails.application.routes.url_helpers.app_account_conversation_url(
      account_id: account.id, id: conversation.display_id
    ) }
  end
end
