class Webhooks::EvolutionController < ActionController::API
  def process_payload
    channel = find_channel
    if channel.blank?
      Rails.logger.warn("[EVOLUTION] Channel not found for phone=#{params[:phone_number]}")
      return head :ok
    end

    if channel.provider != 'evolution_api'
      Rails.logger.warn("[EVOLUTION] Channel provider mismatch for phone=#{params[:phone_number]}")
      return head :ok
    end

    Webhooks::EvolutionEventsJob.perform_later(params.to_unsafe_hash)
    head :ok
  end

  private

  def find_channel
    phone = params[:phone_number].to_s
    Channel::Whatsapp.find_by(phone_number: phone) ||
      Channel::Whatsapp.find_by(phone_number: CGI.unescape(phone)) ||
      Channel::Whatsapp.find_by(phone_number: phone.start_with?('+') ? phone : "+#{phone.delete_prefix('+')}")
  end
end
