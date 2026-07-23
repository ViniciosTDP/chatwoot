require 'rails_helper'

describe Whatsapp::Evolution::InstanceManageService do
  subject(:service) { described_class.new(whatsapp_channel: whatsapp_channel) }

  let(:whatsapp_channel) do
    create(:channel_whatsapp, provider: 'evolution_api', phone_number: '+5511999888777',
                              sync_templates: false, validate_provider_config: false)
  end

  before do
    stub_const('ENV', ENV.to_hash.merge(
                        'EVOLUTION_WEBHOOK_BASE_URL' => 'http://app:3000',
                        'EVOLUTION_API_URL' => '',
                        'EVOLUTION_API_KEY' => ''
                      ))
  end

  describe '#create_instance_and_configure!' do
    it 'creates instance and sets webhook' do
      stub_request(:post, 'http://evolution.test/instance/create')
        .to_return(status: 201, body: { instance: { instanceName: 'cw-test-instance' } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      stub_request(:post, %r{http://evolution\.test/webhook/set/cw-test-instance})
        .with { |req|
          body = JSON.parse(req.body)
          webhook = body['webhook']
          webhook['base64'] == true && webhook['webhookBase64'] == true
        }
        .to_return(status: 200, body: {}.to_json, headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, 'http://evolution.test/instance/connectionState/cw-test-instance')
        .to_return(status: 200, body: { instance: { state: 'close' } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, 'http://evolution.test/instance/connect/cw-test-instance')
        .to_return(status: 200, body: { base64: 'data:image/png;base64,abc' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect { service.create_instance_and_configure! }.not_to raise_error
      expect(whatsapp_channel.reload.provider_config['webhook_media_base64']).to be(true)
    end
  end

  describe '#connection_status' do
    it 'returns state from Evolution and re-applies webhook once for existing instances' do
      stub_request(:post, %r{http://evolution\.test/webhook/set/cw-test-instance})
        .to_return(status: 200, body: {}.to_json, headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, 'http://evolution.test/instance/connectionState/cw-test-instance')
        .to_return(status: 200, body: { instance: { state: 'open' } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, 'http://evolution.test/instance/connect/cw-test-instance')
        .to_return(status: 200, body: {}.to_json, headers: { 'Content-Type' => 'application/json' })

      result = service.connection_status
      expect(result[:state]).to eq('open')
      expect(whatsapp_channel.reload.provider_config['connection_status']).to eq('open')
      expect(whatsapp_channel.provider_config['webhook_media_base64']).to be(true)
      expect(a_request(:post, %r{http://evolution\.test/webhook/set/cw-test-instance})).to have_been_made.once

      # Second call should not re-hit webhook set
      service.connection_status
      expect(a_request(:post, %r{http://evolution\.test/webhook/set/cw-test-instance})).to have_been_made.once
    end
  end
end
