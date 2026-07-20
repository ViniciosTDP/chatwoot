require 'rails_helper'

describe Whatsapp::SendOnWhatsappService do
  let(:whatsapp_channel) do
    create(:channel_whatsapp, provider: 'evolution_api', sync_templates: false, validate_provider_config: false)
  end
  let(:contact_inbox) do
    create(:contact_inbox, inbox: whatsapp_channel.inbox, source_id: '5511999999999')
  end
  let(:conversation) do
    create(:conversation, inbox: whatsapp_channel.inbox, contact_inbox: contact_inbox,
                          contact: contact_inbox.contact)
  end
  let(:message) do
    create(:message, conversation: conversation, message_type: :outgoing, content: 'session only',
                     inbox: whatsapp_channel.inbox, status: :sent)
  end

  it 'always sends session messages for evolution_api even when can_reply? is false' do
    allow(message.conversation).to receive(:can_reply?).and_return(false)

    stub_request(:post, 'http://evolution.test/message/sendText/cw-test-instance')
      .to_return(
        status: 200,
        body: { key: { id: 'EVO_S1' } }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

    described_class.new(message: message).perform
    expect(message.reload.source_id).to eq('EVO_S1')
  end
end
