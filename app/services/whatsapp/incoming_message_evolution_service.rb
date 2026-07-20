class Whatsapp::IncomingMessageEvolutionService
  pattr_initialize [:inbox!, :params!]

  def perform
    event = normalized_event
    case event
    when 'messages.upsert', 'messages_upsert', 'send.message', 'send_message'
      process_message_upsert
    when 'messages.update', 'messages_update'
      process_message_update
    when 'connection.update', 'connection_update'
      process_connection_update
    when 'qrcode.updated', 'qrcode_updated'
      process_qrcode_update
    when 'contacts.upsert', 'contacts.set', 'contacts.update', 'contacts_upsert', 'contacts_set', 'contacts_update'
      process_contacts
    when 'groups.upsert', 'group.update', 'group.participants.update', 'groups_upsert', 'group_update', 'group_participants_update'
      process_groups
    when 'presence.update', 'presence_update'
      process_presence
    when 'call', 'call.update'
      process_call
    else
      Rails.logger.info "[EVOLUTION] Unhandled event: #{event}"
    end
  end

  private

  def normalized_event
    raw = params[:event].presence || params['event'].presence || ''
    raw.to_s.downcase.tr('_', '.')
  end

  def data
    @data ||= data_hash
  end

  def raw_data
    params[:data] || params['data']
  end

  def data_hash
    raw = raw_data
    return raw.with_indifferent_access if raw.is_a?(Hash)

    {}.with_indifferent_access
  end

  def process_message_upsert
    message_upsert_payloads.each do |message_payload|
      process_single_message_upsert(message_payload)
    end
  end

  def message_upsert_payloads
    raw = raw_data
    case raw
    when Hash
      raw[:key].present? ? [raw] : Array.wrap(raw[:messages] || raw['messages'])
    when Array
      raw
    else
      []
    end
  end

  def process_single_message_upsert(message_payload)
    return if message_payload.blank?

    payload = message_payload.with_indifferent_access
    key = (payload[:key] || {}).with_indifferent_access
    source_id = key[:id]
    return if source_id.blank?
    return if Message.find_by(source_id: source_id, inbox_id: inbox.id)

    # Echo of our own outbound — skip if already stored via send path
    return if key[:fromMe] && Message.exists?(source_id: source_id)

    if key[:fromMe]
      create_echo_message(payload, key, source_id)
    else
      create_incoming_message(payload, key, source_id)
    end
  end

  def create_incoming_message(payload, key, source_id)
    jid = effective_jid(key)
    contact_inbox, contact = resolve_contact(jid, payload[:pushName])
    return if contact.blank? || contact.blocked?

    conversation = find_or_create_conversation(contact, contact_inbox, jid)
    message = conversation.messages.build(
      content: extract_text(payload),
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      message_type: :incoming,
      sender: contact,
      source_id: source_id
    )
    attach_media(message, payload)
    message.save!
    message
  end

  def create_echo_message(payload, key, source_id)
    jid = effective_jid(key)
    contact_inbox, contact = resolve_contact(jid, nil)
    return if contact.blank?

    conversation = find_or_create_conversation(contact, contact_inbox, jid)
    message = conversation.messages.build(
      content: extract_text(payload),
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      message_type: :outgoing,
      status: :delivered,
      source_id: source_id,
      additional_attributes: { evolution_echo: true }
    )
    attach_media(message, payload)
    message.save!
  end

  def process_message_update
    message_update_items.each do |item|
      item = item.with_indifferent_access
      key = (item[:key] || {}).with_indifferent_access
      source_id = key[:id] || item[:keyId] || item[:idMessage] || item[:messageId]
      next if source_id.blank?

      message = Message.find_by(source_id: source_id, inbox_id: inbox.id)
      next if message.blank?

      status = map_status(item[:status] || item.dig(:update, :status) || data[:status])
      next if status.blank?

      message.update!(status: status)
    end
  end

  def process_connection_update
    state = data[:state] || data.dig(:instance, 'state') || data[:connection]
    qr = data[:qrcode] || data.dig(:qrcode, 'base64') || data['base64']
    inbox.channel.evolution_instance_service.update_connection_status!(state, qrcode: qr)
  end

  def process_qrcode_update
    qr = data[:qrcode] || data.dig(:qrcode, 'base64') || data['base64'] || data[:code]
    inbox.channel.evolution_instance_service.update_qrcode!(qr) if qr.present?
  end

  def process_contacts
    raw = raw_data
    contacts = Array.wrap(raw.is_a?(Hash) && raw[:contacts] ? raw[:contacts] : raw)
    contacts.each do |contact_data|
      contact_data = contact_data.with_indifferent_access
      jid = jid_from_payload(contact_data[:remoteJid], contact_data[:remoteJidAlt]) || contact_data[:id]
      next if jid.blank?

      _ci, contact = resolve_contact(jid, contact_data[:pushName] || contact_data[:name])
      next if contact.blank?

      attrs = {}
      attrs[:name] = contact_data[:pushName] || contact_data[:name] if (contact_data[:pushName] || contact_data[:name]).present?
      contact.update!(attrs) if attrs.present?
    end
  end

  def process_groups
    group = data.with_indifferent_access
    jid = group[:id] || group[:remoteJid] || group.dig(:subject, :id)
    return if jid.blank? || !group_jid?(jid)

    name = group[:subject] || group.dig(:subject, :subject) || group[:name] || jid
    _ci, contact = resolve_contact(jid, name)
    contact&.update!(name: name.to_s) if name.present?
  end

  def process_presence
    presence = data.with_indifferent_access
    jid = presence[:id] || presence[:remoteJid]
    return if jid.blank?

    _ci, contact = resolve_contact(jid, nil)
    return if contact.blank?

    conversation = Conversation.find_by(inbox_id: inbox.id, contact_id: contact.id)
    return if conversation.blank?

    status = presence[:presences]&.values&.first || presence[:presence] || presence[:lastKnownPresence]
    return if status.blank?

    conversation.update!(
      additional_attributes: conversation.additional_attributes.merge(
        'evolution_presence' => status.to_s
      )
    )
  end

  def process_call
    call = data.with_indifferent_access
    jid = call.dig(:chatId) || call[:from] || call.dig(:key, :remoteJid)
    return if jid.blank?

    contact_inbox, contact = resolve_contact(jid, nil)
    return if contact.blank?

    conversation = find_or_create_conversation(contact, contact_inbox, jid)
    conversation.messages.create!(
      content: I18n.t('conversations.messages.whatsapp.evolution_call_event', default: 'Missed or incoming WhatsApp call event'),
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      message_type: :activity,
      content_attributes: { evolution_call: call.to_h }
    )
  end

  def resolve_contact(jid, push_name)
    identifier = contact_identifier_from_jid(jid)
    return [nil, nil] if identifier.blank?

    contact_inbox = inbox.contact_inboxes.find_by(source_id: identifier)
    if contact_inbox
      contact = contact_inbox.contact
      contact.update(name: push_name) if push_name.present? && contact.name.blank?
      return [contact_inbox, contact]
    end

    contact = inbox.account.contacts.find_by(identifier: identifier) ||
              inbox.account.contacts.find_by(phone_number: phone_e164(identifier))

    if contact.blank?
      contact = inbox.account.contacts.create!(
        name: push_name.presence || identifier,
        phone_number: group_jid?(jid) || identifier.to_s.start_with?('EV.') ? nil : phone_e164(identifier),
        identifier: identifier,
        additional_attributes: if group_jid?(jid) || identifier.to_s.start_with?('EV.')
                                 { 'evolution_group' => true, 'jid' => jid }
                               else
                                 { 'jid' => jid }
                               end
      )
    end

    contact_inbox = inbox.contact_inboxes.create!(contact: contact, source_id: identifier)
    [contact_inbox, contact]
  end

  def find_or_create_conversation(contact, contact_inbox, jid)
    conversation = Conversation.find_by(inbox_id: inbox.id, contact_id: contact.id)
    return conversation if conversation.present?

    Conversation.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      contact_id: contact.id,
      contact_inbox_id: contact_inbox.id,
      additional_attributes: group_jid?(jid) ? { 'mail_subject' => contact.name, 'evolution_group' => true } : {}
    )
  end

  def contact_identifier_from_jid(jid)
    raw = jid.to_s.split('@').first.presence
    return if raw.blank?
    return "EV.#{raw}" if group_jid?(jid)

    raw
  end

  def effective_jid(key)
    jid_from_payload(key[:remoteJid], key[:remoteJidAlt])
  end

  def jid_from_payload(jid, alt = nil)
    jid = jid.to_s
    alt = alt.to_s
    return alt if jid.end_with?('@lid') && alt.present?

    jid.presence
  end

  def message_update_items
    raw = raw_data
    case raw
    when Array then raw
    when Hash then [raw]
    else []
    end
  end

  def group_jid?(jid)
    jid.to_s.end_with?('@g.us') || jid.to_s.start_with?('EV.')
  end

  def phone_e164(identifier)
    return if identifier.to_s.start_with?('EV.')

    digits = identifier.to_s.gsub(/\D/, '')
    return if digits.blank?

    "+#{digits}"
  end

  def extract_text(payload)
    message = (payload[:message] || {}).with_indifferent_access
    message[:conversation].presence ||
      message.dig(:extendedTextMessage, :text).presence ||
      message.dig(:imageMessage, :caption).presence ||
      message.dig(:videoMessage, :caption).presence ||
      message.dig(:documentMessage, :caption).presence ||
      message.dig(:buttonsResponseMessage, :selectedDisplayText).presence ||
      message.dig(:listResponseMessage, :title).presence ||
      message.dig(:templateButtonReplyMessage, :selectedDisplayText).presence ||
      ''
  end

  def attach_media(message, payload)
    msg = (payload[:message] || {}).with_indifferent_access
    base64 = payload[:message] && (payload.dig('message', 'base64') || payload[:base64])
    # Evolution with webhookBase64 may nest base64 differently
    media_info = media_from_message(msg)
    return if media_info.blank? && base64.blank?

    return attach_base64(message, base64, media_info) if base64.present?

    # Fallback: no remote download URL without getBase64 — skip silently if no base64
    nil
  end

  def media_from_message(msg)
    %w[imageMessage videoMessage audioMessage documentMessage stickerMessage].each do |key|
      return [key, msg[key]] if msg[key].present?
    end
    nil
  end

  def attach_base64(message, base64_data, media_info)
    raw = base64_data.to_s
    raw = raw.split(',', 2).last if raw.include?(',')
    binary = Base64.decode64(raw)
    filename = media_info&.last&.dig('fileName').presence || "evolution-#{SecureRandom.hex(4)}"
    content_type = media_info&.last&.dig('mimetype').presence || 'application/octet-stream'
    file_type = file_type_from_media_key(media_info&.first)

    message.attachments.new(
      account_id: message.account_id,
      file_type: file_type,
      file: {
        io: StringIO.new(binary),
        filename: filename,
        content_type: content_type
      }
    )
  rescue StandardError => e
    Rails.logger.warn "[EVOLUTION] attach_media failed: #{e.message}"
  end

  def file_type_from_media_key(key)
    case key
    when 'imageMessage', 'stickerMessage' then :image
    when 'audioMessage' then :audio
    when 'videoMessage' then :video
    else :file
    end
  end

  def map_status(status)
    case status.to_s.upcase
    when 'PENDING', 'SERVER_ACK', '1' then :sent
    when 'DELIVERY_ACK', '2', 'DELIVERED' then :delivered
    when 'READ', '3', 'PLAYED', '4' then :read
    when 'ERROR', 'DELETED' then :failed
    end
  end
end
