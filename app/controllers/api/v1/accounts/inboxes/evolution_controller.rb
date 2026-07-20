class Api::V1::Accounts::Inboxes::EvolutionController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox
  before_action :ensure_evolution_provider!

  def status
    result = @inbox.channel.evolution_instance_service.connection_status
    render json: result
  end

  def reconnect
    result = @inbox.channel.evolution_instance_service.reconnect!
    render json: result
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id] || params[:id])
    authorize @inbox, :show?
  end

  def ensure_evolution_provider!
    return if @inbox.channel.is_a?(Channel::Whatsapp) && @inbox.channel.provider == 'evolution_api'

    render json: { error: 'Inbox is not an Evolution WhatsApp channel' }, status: :unprocessable_entity
  end
end
