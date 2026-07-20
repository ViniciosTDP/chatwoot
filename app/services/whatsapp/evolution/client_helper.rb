module Whatsapp::Evolution::ClientHelper
  private

  # In local Docker, EVOLUTION_API_URL / EVOLUTION_API_KEY always win so the
  # UI can keep showing http://localhost:8080 without breaking server-side calls.
  def evolution_api_base_path
    env_url = ENV['EVOLUTION_API_URL'].to_s.sub(%r{/\z}, '')
    return env_url if env_url.present?

    whatsapp_channel.provider_config.to_h.with_indifferent_access['api_url'].to_s.sub(%r{/\z}, '')
  end

  def evolution_api_headers
    key = ENV['EVOLUTION_API_KEY'].presence ||
          whatsapp_channel.provider_config.to_h.with_indifferent_access['api_key'].to_s
    {
      'apikey' => key.to_s,
      'Content-Type' => 'application/json'
    }
  end

  def evolution_instance_name
    whatsapp_channel.provider_config.to_h.with_indifferent_access['instance_name']
  end
end
