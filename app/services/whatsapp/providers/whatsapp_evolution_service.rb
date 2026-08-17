class Whatsapp::Providers::WhatsappEvolutionService < Whatsapp::Providers::BaseService
  include Whatsapp::Evolution::ClientHelper

  TYPING_DELAY_MIN_MS = 800
  TYPING_DELAY_MAX_MS = 4000
  TYPING_MS_PER_CHAR = 40
  SEND_PRESENCE_TIMEOUT_SECONDS = 15

  EVOLUTION_ERROR_DISCONNECTED = 'EVOLUTION_DISCONNECTED'
  EVOLUTION_ERROR_BANNED = 'EVOLUTION_BANNED'
  EVOLUTION_ERROR_UNAVAILABLE = 'EVOLUTION_UNAVAILABLE'
  EVOLUTION_UNAVAILABLE_ERRORS = [
    Net::OpenTimeout,
    Net::ReadTimeout,
    Errno::ECONNREFUSED,
    Errno::EHOSTUNREACH,
    SocketError,
    Timeout::Error
  ].freeze

  def send_message(phone_number, message)
    @message = message
    maybe_simulate_typing(phone_number, message)

    if message.attachments.present?
      send_attachment_message(phone_number, message)
    elsif message.content_type == 'input_select'
      send_interactive_message(phone_number, message)
    else
      send_text_message(phone_number, message)
    end
  rescue *EVOLUTION_UNAVAILABLE_ERRORS => e
    mark_unavailable(message, e)
    nil
  end

  def send_template(phone_number, template_info, message)
    # Evolution (Baileys) has no Meta HSM templates. Proactive OS/HSM on Evolution
    # is session text. Cloud API inboxes use WhatsappCloudService#send_template.
    body = template_info[:processed_params].presence ||
           template_info.dig(:parameters)&.map { |p| p.is_a?(Hash) ? p['text'] || p[:text] : p }&.join(' ') ||
           message&.outgoing_content

    return handle_template_fallback_error(message) if body.blank?

    maybe_simulate_typing(phone_number, message)

    response = HTTParty.post(
      "#{api_base_path}/message/sendText/#{instance_name}",
      headers: api_headers,
      body: {
        number: normalize_number(phone_number),
        text: body.to_s
      }.to_json
    )
    process_response(response, message)
  rescue *EVOLUTION_UNAVAILABLE_ERRORS => e
    mark_unavailable(message, e)
    nil
  end

  def sync_templates
    whatsapp_channel.mark_message_templates_updated
  end

  def validate_provider_config?
    config = whatsapp_channel.provider_config.to_h.with_indifferent_access
    return false if config['api_url'].blank? || config['api_key'].blank?

    base = api_base_path
    Rails.logger.info "[EVOLUTION] validate_provider_config url=#{base} key_present=#{config['api_key'].present?}"

    response = HTTParty.get(
      "#{base}/instance/fetchInstances",
      headers: api_headers,
      timeout: 10
    )
    response.success?
  rescue StandardError => e
    Rails.logger.error "[EVOLUTION] validate_provider_config failed: #{e.message}"
    false
  end

  def api_headers
    evolution_api_headers
  end

  def media_url(_media_id)
    "#{api_base_path}/chat/getBase64FromMediaMessage/#{instance_name}"
  end

  def error_message(response)
    parsed = response.parsed_response
    return parsed if parsed.is_a?(String)

    if parsed.is_a?(Hash)
      nested = parsed.dig('response', 'message')
      nested = nested.join(', ') if nested.is_a?(Array)
      return nested if nested.present?
      return parsed['message'] || parsed['error'] || parsed.to_s
    end

    response.body
  end

  def process_response(response, message)
    parsed = response.parsed_response
    if response.success?
      message_id = extract_message_id(parsed)
      return message_id if message_id.present?
    end

    handle_error(response, message)
    nil
  end

  def handle_error(response, message)
    detail = error_message(response).to_s
    code = classify_evolution_error(response, detail)
    stable = [code, detail.presence].compact.join(': ')

    Rails.logger.error "[EVOLUTION] send failed instance=#{instance_name} code=#{code || 'UNKNOWN'} body=#{response.body}"
    return if message.blank? || stable.blank?

    message.external_error = stable
    message.status = :failed
    message.save!
  end

  private

  def api_base_path
    evolution_api_base_path
  end

  def instance_name
    evolution_instance_name
  end

  def normalize_number(phone_number)
    value = phone_number.to_s
    # Group conversations use EV.<groupId> as contact_inbox source_id
    return "#{value.delete_prefix('EV.')}@g.us" if value.start_with?('EV.')

    value.gsub(/\D/, '')
  end

  def extract_message_id(parsed)
    return if parsed.blank?
    return parsed.dig('key', 'id') if parsed.is_a?(Hash)
    return parsed.first.dig('key', 'id') if parsed.is_a?(Array) && parsed.first.is_a?(Hash)

    nil
  end

  def maybe_simulate_typing(phone_number, message)
    return unless simulate_typing?(message)

    delay_ms = typing_delay_ms(message)
    response = HTTParty.post(
      "#{api_base_path}/chat/sendPresence/#{instance_name}",
      headers: api_headers,
      timeout: SEND_PRESENCE_TIMEOUT_SECONDS,
      body: {
        number: normalize_number(phone_number),
        delay: delay_ms,
        presence: 'composing'
      }.to_json
    )

    return if response.success?

    Rails.logger.error(
      "[EVOLUTION] sendPresence failed instance=#{instance_name} status=#{response.code} body=#{response.body}"
    )
  rescue StandardError => e
    Rails.logger.error("[EVOLUTION] sendPresence failed instance=#{instance_name} error=#{e.message}")
  end

  def simulate_typing?(message)
    return false if message.blank?

    attrs = (message.content_attributes || {}).with_indifferent_access
    return true if ActiveModel::Type::Boolean.new.cast(attrs[:simulate_typing])
    return true if attrs[:origem].to_s.casecmp('mensageria').zero?

    false
  end

  def typing_delay_ms(message)
    base = (message&.outgoing_content.to_s.length * TYPING_MS_PER_CHAR).clamp(TYPING_DELAY_MIN_MS, TYPING_DELAY_MAX_MS)
    jitter_factor = 1 + ((rand * 0.4) - 0.2)
    (base * jitter_factor).round.clamp(TYPING_DELAY_MIN_MS, TYPING_DELAY_MAX_MS)
  end

  def mark_unavailable(message, error)
    Rails.logger.error(
      "[EVOLUTION] send failed instance=#{instance_name} code=#{EVOLUTION_ERROR_UNAVAILABLE} error=#{error.message}"
    )
    return if message.blank?

    message.external_error = "#{EVOLUTION_ERROR_UNAVAILABLE}: #{error.message}"
    message.status = :failed
    message.save!
  end

  def classify_evolution_error(response, detail = nil)
    status = response.respond_to?(:code) ? response.code.to_i : 0
    body = detail.to_s.downcase
    body = error_message(response).to_s.downcase if body.blank?

    return EVOLUTION_ERROR_BANNED if status == 403 || body.match?(/banned|forbidden|\b403\b/)
    return EVOLUTION_ERROR_DISCONNECTED if body.match?(/disconnect|logged out|logout|not connected|connection closed|instance.*(close|offline)/)
    return EVOLUTION_ERROR_UNAVAILABLE if status.zero? || status >= 500 || body.match?(/timeout|unavailable|econnrefused/)

    nil
  end

  def send_text_message(phone_number, message)
    response = HTTParty.post(
      "#{api_base_path}/message/sendText/#{instance_name}",
      headers: api_headers,
      body: {
        number: normalize_number(phone_number),
        text: message.outgoing_content.to_s,
        quoted: quoted_message_payload(message)
      }.compact.to_json
    )
    process_response(response, message)
  end

  def send_attachment_message(phone_number, message)
    attachment = message.attachments.first
    return send_voice_message(phone_number, message, attachment) if voice_message?(attachment)

    mediatype = media_type_for(attachment)
    content_type = attachment.file.content_type
    body = {
      number: normalize_number(phone_number),
      mediatype: mediatype,
      mimetype: content_type,
      media: media_as_base64(attachment),
      fileName: attachment.file.filename.to_s
    }
    caption = message.outgoing_content.to_s
    # Evolution/WhatsApp reject empty captions on audio; Cloud API also skips caption for audio.
    body[:caption] = caption if caption.present? && mediatype != 'audio'

    response = HTTParty.post(
      "#{api_base_path}/message/sendMedia/#{instance_name}",
      headers: api_headers,
      body: body.to_json
    )
    process_response(response, message)
  end

  # Microphone recordings are tagged is_voice_message; Evolution's sendWhatsAppAudio
  # renders them as native WhatsApp PTT (waveform + playback speed).
  def send_voice_message(phone_number, message, attachment)
    response = HTTParty.post(
      "#{api_base_path}/message/sendWhatsAppAudio/#{instance_name}",
      headers: api_headers,
      body: {
        number: normalize_number(phone_number),
        audio: media_as_base64(attachment)
      }.to_json
    )
    process_response(response, message)
  end

  def voice_message?(attachment)
    attachment.file_type == 'audio' &&
      ActiveModel::Type::Boolean.new.cast(attachment.meta&.dig('is_voice_message'))
  end

  # Evolution's isBase64() rejects data-URI prefixes (data:mime;base64,...).
  # Send raw base64; mimetype/fileName carry the type metadata.
  def media_as_base64(attachment)
    Base64.strict_encode64(attachment.file.blob.download)
  end

  def send_interactive_message(phone_number, message)
    items = message.content_attributes['items'] || []
    if items.length <= 3
      send_buttons_message(phone_number, message, items)
    else
      send_list_message(phone_number, message, items)
    end
  end

  def send_buttons_message(phone_number, message, items)
    buttons = items.map.with_index do |item, index|
      {
        buttonId: item['value'].presence || "btn_#{index}",
        buttonText: { displayText: item['title'].to_s.truncate(20) },
        type: 1
      }
    end

    response = HTTParty.post(
      "#{api_base_path}/message/sendButtons/#{instance_name}",
      headers: api_headers,
      body: {
        number: normalize_number(phone_number),
        title: message.outgoing_content.to_s.truncate(60),
        description: message.outgoing_content.to_s,
        buttons: buttons
      }.to_json
    )
    process_response(response, message)
  rescue StandardError
    # Fallback to plain text if buttons endpoint is unavailable
    send_text_message(phone_number, message)
  end

  def send_list_message(phone_number, message, items)
    rows = items.map.with_index do |item, index|
      {
        rowId: item['value'].presence || "row_#{index}",
        title: item['title'].to_s.truncate(24),
        description: item['description'].to_s.truncate(72)
      }
    end

    response = HTTParty.post(
      "#{api_base_path}/message/sendList/#{instance_name}",
      headers: api_headers,
      body: {
        number: normalize_number(phone_number),
        title: message.outgoing_content.to_s.truncate(60),
        description: message.outgoing_content.to_s,
        buttonText: I18n.t('conversations.messages.whatsapp.list_button_label'),
        sections: [{ title: 'Options', rows: rows }]
      }.to_json
    )
    process_response(response, message)
  rescue StandardError
    send_text_message(phone_number, message)
  end

  def media_type_for(attachment)
    case attachment.file_type
    when 'image' then 'image'
    when 'audio' then 'audio'
    when 'video' then 'video'
    else 'document'
    end
  end

  def quoted_message_payload(message)
    return if message.content_attributes.blank?

    in_reply_to = message.content_attributes['in_reply_to']
    return if in_reply_to.blank?

    replied = message.conversation.messages.find_by(id: in_reply_to)
    return if replied&.source_id.blank?

    { key: { id: replied.source_id } }
  end

  def handle_template_fallback_error(message)
    return if message.blank?

    message.external_error = 'Evolution API does not support Meta templates; no message body available'
    message.status = :failed
    message.save!
    nil
  end
end
