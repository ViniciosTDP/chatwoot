require 'rails_helper'

describe 'Webhooks::Evolution', type: :request do
  let(:whatsapp_channel) do
    create(:channel_whatsapp, provider: 'evolution_api', phone_number: '+5511999888777',
                              sync_templates: false, validate_provider_config: false)
  end

  before { whatsapp_channel }

  describe 'POST /webhooks/evolution/:phone_number' do
    it 'enqueues EvolutionEventsJob' do
      expect do
        post '/webhooks/evolution/+5511999888777',
             params: {
               event: 'messages.upsert',
               data: {
                 key: { id: '1', remoteJid: '5511@s.whatsapp.net', fromMe: false },
                 message: { conversation: 'hi' }
               }
             },
             as: :json
      end.to have_enqueued_job(Webhooks::EvolutionEventsJob)

      expect(response).to have_http_status(:ok)
    end

    it 'returns ok when channel is missing' do
      post '/webhooks/evolution/+00000000000', params: { event: 'messages.upsert' }, as: :json
      expect(response).to have_http_status(:ok)
    end
  end
end
