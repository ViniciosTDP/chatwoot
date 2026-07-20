class Whatsapp::Providers::WhatsappEvolutionService < Whatsapp::Providers::BaseService
  include Whatsapp::Evolution::ClientHelper

  def send_message(phone_number, message)
    @message = message

    if message.attachments.present?
      send_attachment_message(phone_number, message)
    elsif message.content_type == 'input_select'
      send_interactive_message(phone_number, message)
    else
      send_text_message(phone_number, message)
    end
  end

  def send_template(phone_number, template_info, message)
    # Evolution has no Meta HSM templates — send session text built from template params.
    body = template_info[:processed_params].presence ||
           template_info.dig(:parameters)&.map { |p| p.is_a?(Hash) ? p['text'] || p[:text] : p }&.join(' ') ||
           message&.outgoing_content

    return handle_template_fallback_error(message) if body.blank?

    response = HTTParty.post(
      "#{api_base_path}/message/sendText/#{instance_name}",
      headers: api_headers,
      body: {
        number: normalize_number(phone_number),
        text: body.to_s
      }.to_json
    )
    process_response(response, message)
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
    return parsed['message'] || parsed['error'] || parsed.to_s if parsed.is_a?(Hash)

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
    mediatype = media_type_for(attachment)
    response = HTTParty.post(
      "#{api_base_path}/message/sendMedia/#{instance_name}",
      headers: api_headers,
      body: {
        number: normalize_number(phone_number),
        mediatype: mediatype,
        mimetype: attachment.file.content_type,
        caption: message.outgoing_content.to_s,
        media: attachment.download_url,
        fileName: attachment.file.filename.to_s
      }.to_json
    )
    process_response(response, message)
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
