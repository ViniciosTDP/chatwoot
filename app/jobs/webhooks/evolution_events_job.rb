class Webhooks::EvolutionEventsJob < ApplicationJob
  queue_as :low

  def perform(params = {})
    params = params.with_indifferent_access
    channel = find_channel(params)
    return if channel.blank?
    return if channel.account.blank? || !channel.account.active?

    Whatsapp::IncomingMessageEvolutionService.new(inbox: channel.inbox, params: params).perform
  end

  private

  def find_channel(params)
    phone = params[:phone_number].to_s
    Channel::Whatsapp.find_by(phone_number: phone, provider: 'evolution_api') ||
      Channel::Whatsapp.find_by(phone_number: CGI.unescape(phone), provider: 'evolution_api')
  end
end
