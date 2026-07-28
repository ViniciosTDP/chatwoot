class Whatsapp::Evolution::InstanceManageService
  include Whatsapp::Evolution::ClientHelper

  pattr_initialize [:whatsapp_channel!]

  WEBHOOK_EVENTS = %w[
    APPLICATION_STARTUP
    QRCODE_UPDATED
    MESSAGES_SET
    MESSAGES_UPSERT
    MESSAGES_UPDATE
    MESSAGES_DELETE
    SEND_MESSAGE
    CONTACTS_SET
    CONTACTS_UPSERT
    CONTACTS_UPDATE
    PRESENCE_UPDATE
    CHATS_SET
    CHATS_UPSERT
    CHATS_UPDATE
    CHATS_DELETE
    GROUPS_UPSERT
    GROUP_UPDATE
    GROUP_PARTICIPANTS_UPDATE
    CONNECTION_UPDATE
    CALL
  ].freeze

  def create_instance_and_configure!
    ensure_instance_name!
    create_instance!
    set_webhook!
    refresh_connection_state!
    whatsapp_channel
  end

  def set_webhook!
    response = HTTParty.post(
      "#{api_base_path}/webhook/set/#{instance_name}",
      headers: api_headers,
      body: {
        webhook: {
          enabled: true,
          url: webhook_url,
          webhookByEvents: false,
          # Evolution v2 expects `base64`; keep `webhookBase64` for older builds.
          base64: true,
          webhookBase64: true,
          events: WEBHOOK_EVENTS
        }
      }.to_json
    )
    raise "Evolution webhook setup failed: #{response.body}" unless response.success?

    update_provider_config!('webhook_media_base64' => true)
    true
  end

  def connection_status
    ensure_webhook_media_base64!
    response = HTTParty.get(
      "#{api_base_path}/instance/connectionState/#{instance_name}",
      headers: api_headers,
      timeout: 8
    )
    state = response.parsed_response.is_a?(Hash) ? response.parsed_response.dig('instance', 'state') : nil
    state ||= response.parsed_response.is_a?(Hash) ? response.parsed_response['state'] : nil
    update_connection_status!(state) if state.present?
    {
      state: state || whatsapp_channel.provider_config['connection_status'],
      qrcode: fetch_qrcode,
      instance_name: instance_name
    }
  rescue StandardError => e
    Rails.logger.error "[EVOLUTION] connection_status failed: #{e.message}"
    {
      state: whatsapp_channel.provider_config['connection_status'],
      qrcode: normalize_qrcode(whatsapp_channel.provider_config['qrcode_base64']),
      instance_name: instance_name,
      error: e.message
    }
  end

  def reconnect!
    ensure_webhook_media_base64!(force: true)
    response = HTTParty.get(
      "#{api_base_path}/instance/connect/#{instance_name}",
      headers: api_headers,
      timeout: 8
    )
    qr = extract_qrcode(response.parsed_response)
    update_provider_config!('qrcode_base64' => qr, 'connection_status' => 'connecting') if qr.present?
    connection_status
  end

  def delete_instance!
    HTTParty.delete(
      "#{api_base_path}/instance/delete/#{instance_name}",
      headers: api_headers
    )
  rescue StandardError => e
    Rails.logger.warn "[EVOLUTION] delete_instance failed: #{e.message}"
  end

  def update_connection_status!(state, qrcode: nil)
    attrs = { 'connection_status' => normalize_state(state) }
    normalized_qr = normalize_qrcode(qrcode)
    attrs['qrcode_base64'] = normalized_qr if normalized_qr.present?
    attrs['qrcode_base64'] = nil if %w[open connected].include?(normalize_state(state))
    update_provider_config!(attrs)
  end

  def update_qrcode!(qrcode)
    normalized_qr = normalize_qrcode(qrcode)
    return if normalized_qr.blank?

    update_provider_config!('qrcode_base64' => normalized_qr, 'connection_status' => 'qr')
  end

  private

  # Re-apply webhook once for existing instances so they pick up base64: true.
  # Polled every 3s during QR setup — gate with provider_config flag.
  def ensure_webhook_media_base64!(force: false)
    return if !force && whatsapp_channel.provider_config['webhook_media_base64']

    set_webhook!
  rescue StandardError => e
    Rails.logger.warn "[EVOLUTION] ensure_webhook_media_base64 failed: #{e.message}"
  end

  def create_instance!
    response = HTTParty.post(
      "#{api_base_path}/instance/create",
      headers: api_headers,
      body: {
        instanceName: instance_name,
        token: whatsapp_channel.provider_config['webhook_token'],
        qrcode: true,
        integration: 'WHATSAPP-BAILEYS'
      }.to_json
    )

    # 403/409 often mean instance already exists — continue to webhook setup
    return true if response.success? || [403, 409].include?(response.code)

    raise "Evolution instance create failed: #{response.body}"
  end

  def fetch_qrcode
    cached = normalize_qrcode(whatsapp_channel.provider_config['qrcode_base64'])
    if cached.present?
      # Heal legacy rows that persisted the raw Evolution payload Hash
      if whatsapp_channel.provider_config['qrcode_base64'].is_a?(Hash)
        update_provider_config!('qrcode_base64' => cached)
      end
      return cached
    end

    response = HTTParty.get(
      "#{api_base_path}/instance/connect/#{instance_name}",
      headers: api_headers,
      timeout: 8
    )
    qr = extract_qrcode(response.parsed_response)
    update_provider_config!('qrcode_base64' => qr) if qr.present?
    qr
  rescue StandardError
    normalize_qrcode(whatsapp_channel.provider_config['qrcode_base64'])
  end

  # Always return a data-URI / base64 string for the frontend <img> src.
  # Webhooks and older caches may store the raw Evolution Hash ({ base64, code, ... }).
  def normalize_qrcode(payload)
    extract_qrcode(payload)
  end

  def extract_qrcode(payload)
    return if payload.blank?
    return payload if payload.is_a?(String) && payload.start_with?('data:image')

    if payload.is_a?(Hash)
      payload = payload.with_indifferent_access
      return payload[:base64] if payload[:base64].present?
      nested = payload[:qrcode]
      return extract_qrcode(nested) if nested.present?
      return payload[:code] if payload[:code].to_s.start_with?('data:image')
    end

    nil
  end

  def refresh_connection_state!
    connection_status
  end

  def ensure_instance_name!
    return if whatsapp_channel.provider_config['instance_name'].present?

    name = "cw-#{whatsapp_channel.account_id}-#{SecureRandom.hex(4)}"
    update_provider_config!('instance_name' => name)
  end

  def update_provider_config!(attrs)
    whatsapp_channel.provider_config = whatsapp_channel.provider_config.merge(attrs.stringify_keys)
    whatsapp_channel.save!(validate: false)
  end

  def normalize_state(state)
    case state.to_s.downcase
    when 'open', 'connected' then 'open'
    when 'close', 'closed', 'disconnected' then 'close'
    when 'connecting', 'refused' then 'connecting'
    else state.to_s.downcase.presence || 'created'
    end
  end

  def webhook_url
    base = ENV.fetch('EVOLUTION_WEBHOOK_BASE_URL', ENV.fetch('FRONTEND_URL', '')).to_s.sub(%r{/\z}, '')
    phone = CGI.escape(whatsapp_channel.phone_number.to_s)
    "#{base}/webhooks/evolution/#{phone}"
  end

  def api_base_path
    evolution_api_base_path
  end

  def instance_name
    evolution_instance_name
  end

  def api_headers
    evolution_api_headers
  end
end
