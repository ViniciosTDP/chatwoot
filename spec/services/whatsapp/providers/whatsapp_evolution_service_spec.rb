require 'rails_helper'

describe Whatsapp::Providers::WhatsappEvolutionService do
  subject(:service) { described_class.new(whatsapp_channel: whatsapp_channel) }

  let(:whatsapp_channel) do
    create(:channel_whatsapp, provider: 'evolution_api', sync_templates: false, validate_provider_config: false)
  end
  let(:conversation) { create(:conversation, inbox: whatsapp_channel.inbox) }
  let(:message) do
    create(:message, conversation: conversation, message_type: :outgoing, content: 'hello evolution',
                     inbox: whatsapp_channel.inbox)
  end
  let(:response_headers) { { 'Content-Type' => 'application/json' } }
  let(:evolution_response) { { key: { id: 'EVO_MSG_1', remoteJid: '5511999999999@s.whatsapp.net', fromMe: true } } }

  describe '#send_message' do
    it 'sends a text message via Evolution API' do
      stub_request(:post, 'http://evolution.test/message/sendText/cw-test-instance')
        .with(
          body: hash_including('number' => '5511999999999', 'text' => 'hello evolution')
        )
        .to_return(status: 200, body: evolution_response.to_json, headers: response_headers)

      expect(service.send_message('+5511999999999', message)).to eq('EVO_MSG_1')
    end

    it 'sends media via sendMedia endpoint' do
      attachment = message.attachments.new(account_id: message.account_id, file_type: :image)
      attachment.file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'avatar.png', content_type: 'image/png')

      stub_request(:post, 'http://evolution.test/message/sendMedia/cw-test-instance')
        .to_return(status: 200, body: evolution_response.to_json, headers: response_headers)

      expect(service.send_message('5511999999999', message)).to eq('EVO_MSG_1')
    end
  end

  describe '#validate_provider_config?' do
    it 'returns true when Evolution responds successfully' do
      stub_request(:get, 'http://evolution.test/instance/fetchInstances')
        .to_return(status: 200, body: [].to_json, headers: response_headers)

      expect(service.validate_provider_config?).to be(true)
    end

    it 'returns false when Evolution is unreachable' do
      stub_request(:get, 'http://evolution.test/instance/fetchInstances')
        .to_return(status: 401, body: { error: 'unauthorized' }.to_json, headers: response_headers)

      expect(service.validate_provider_config?).to be(false)
    end

    it 'rewrites localhost api_url to EVOLUTION_API_URL inside Docker' do
      whatsapp_channel.provider_config = whatsapp_channel.provider_config.merge('api_url' => 'http://localhost:8080')
      whatsapp_channel.save!(validate: false)
      stub_const('ENV', ENV.to_hash.merge('EVOLUTION_API_URL' => 'http://evolution:8080'))

      stub_request(:get, 'http://evolution:8080/instance/fetchInstances')
        .to_return(status: 200, body: [].to_json, headers: response_headers)

      expect(service.validate_provider_config?).to be(true)
    end

    it 'prefers EVOLUTION_API_URL from ENV over provider_config' do
      whatsapp_channel.provider_config = whatsapp_channel.provider_config.merge(
        'api_url' => 'http://localhost:8080',
        'api_key' => 'wrong-key'
      )
      whatsapp_channel.save!(validate: false)
      stub_const('ENV', ENV.to_hash.merge(
                          'EVOLUTION_API_URL' => 'http://evolution:8080',
                          'EVOLUTION_API_KEY' => 'chatwoot_evolution_dev_key'
                        ))

      stub_request(:get, 'http://evolution:8080/instance/fetchInstances')
        .with(headers: { 'Apikey' => 'chatwoot_evolution_dev_key' })
        .to_return(status: 200, body: [].to_json, headers: response_headers)

      expect(service.validate_provider_config?).to be(true)
    end
  end

  describe '#sync_templates' do
    it 'marks templates as updated without calling Meta' do
      expect { service.sync_templates }.not_to raise_error
      expect(whatsapp_channel.reload.message_templates_last_updated).to be_present
    end
  end
end
