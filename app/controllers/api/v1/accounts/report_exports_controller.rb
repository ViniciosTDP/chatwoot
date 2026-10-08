class Api::V1::Accounts::ReportExportsController < Api::V1::Accounts::BaseController
  before_action :set_export, only: [:show, :download]

  def index
    exports = own_exports.order(created_at: :desc).limit(20).select(&:permitted?)
    render json: exports.map { |export| serialize(export) }
  end

  def show
    render json: serialize(@export)
  end

  def create
    attributes = export_params
    candidate = ReportExport.new(account: Current.account, user: Current.user, **attributes)
    raise Pundit::NotAuthorizedError unless candidate.permitted?

    Reports::PdfFilters.new(candidate).validate!
    created = false
    Current.account_user.with_lock do
      @export = own_exports.where(status: %w[pending processing], **attributes).first
      unless @export
        @export = ReportExport.create!(account: Current.account, user: Current.user, expires_at: 24.hours.from_now, **attributes)
        created = true
      end
    end
    Reports::ExportPdfJob.perform_later(@export.id) if created
    render json: serialize(@export), status: :accepted
  rescue CustomExceptions::ReportPdf => e
    render json: { error_code: e.code }, status: :unprocessable_entity
  end

  def download
    return head :conflict unless @export.completed? && @export.document.attached?

    response.headers['Cache-Control'] = 'private, no-store'
    send_data @export.document.download, type: 'application/pdf', disposition: 'attachment', filename: @export.document.filename.to_s
  end

  private

  def own_exports
    ReportExport.available.where(account: Current.account, user: Current.user)
  end

  def set_export
    @export = own_exports.find(params[:id])
    raise Pundit::NotAuthorizedError unless @export.permitted?
  end

  def export_params
    permitted = params.permit(:report_type, filters: [
                                :since, :until, :group_by, :timezone_offset, :business_hours, :id,
                                :inbox_id, :team_id, :rating, :assigned_agent_id, :sla_policy_id, :label_list, { user_ids: [], label_list: [] }
                              ])
    { report_type: permitted[:report_type], filters: permitted.fetch(:filters, {}).to_h }
  end

  def serialize(export)
    export.as_json(only: [:id, :report_type, :status, :error_code, :created_at, :processed_at, :expires_at])
  end
end
