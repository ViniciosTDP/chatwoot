class Reports::CsatPdfData
  include DateRangeHelper
  attr_reader :account, :params

  def initialize(export)
    @account = export.account
    @params = Reports::PdfFilters.new(export).builder_params
  end

  def build
    raise CustomExceptions::ReportPdf, 'too_large' if total > ReportExport::MAX_ROWS

    { metrics: metrics, headers: headers,
      rows: query.includes(:assigned_agent, :contact, :conversation).order(:created_at, :id).map { |response| row(response) }, charts: [chart] }
  end

  private

  def query
    @query ||= account.csat_survey_responses.filter_by_created_at(range).filter_by_assigned_agent_id(params[:user_ids])
                      .filter_by_inbox_id(params[:inbox_id]).filter_by_team_id(params[:team_id]).filter_by_rating(params[:rating])
  end

  def total
    @total ||= query.count
  end

  def ratings
    @ratings ||= query.group(:rating).count
  end

  def metrics
    sent = account.messages.input_csat.where(created_at: range).count
    satisfaction = percent(ratings.fetch(4, 0) + ratings.fetch(5, 0), total)
    [[Reports::PdfText.t('report_pdf.responses'), total], [Reports::PdfText.t('report_pdf.satisfaction'), satisfaction],
     [Reports::PdfText.t('report_pdf.response_rate'), percent(total, sent)]]
  end

  def chart
    { type: :bar, unit: :count, labels: (1..5).map(&:to_s),
      series: [{ name: Reports::PdfText.t('report_pdf.responses'), values: (1..5).map { |rating| ratings.fetch(rating, 0) } }] }
  end

  def percent(numerator, denominator)
    Reports::PdfText.percent(denominator.zero? ? 0 : numerator * 100.0 / denominator)
  end

  def headers
    keys = %w[agent_name rating feedback contact_name contact_email_address contact_phone_number link_to_the_conversation recorded_at]
    keys << 'review_notes' if ChatwootApp.enterprise?
    keys.map { |key| Reports::PdfText.t("report_pdf.csat_headers.#{key}") }
  end

  def row(response)
    agent = response.assigned_agent
    values = [agent && "#{agent.name} (#{agent.email})", response.rating, response.feedback_message,
              response.contact&.name, response.contact&.email, response.contact&.phone_number,
              conversation_link(response.conversation), recorded_at(response)]
    values << response.csat_review_notes if ChatwootApp.enterprise?
    values
  end

  def recorded_at(response)
    response.created_at.getlocal((params.fetch(:timezone_offset, 0).to_f * 3600).to_i).strftime('%d/%m/%Y %H:%M')
  end

  def conversation_link(conversation)
    { text: "##{conversation.display_id}", href: Rails.application.routes.url_helpers.app_account_conversation_url(
      account_id: account.id, id: conversation.display_id
    ) }
  end
end
