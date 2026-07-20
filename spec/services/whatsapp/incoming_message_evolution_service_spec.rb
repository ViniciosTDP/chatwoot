require 'rails_helper'

describe Whatsapp::IncomingMessageEvolutionService do
  let(:whatsapp_channel) do
    create(:channel_whatsapp, provider: 'evolution_api', sync_templates: false, validate_provider_config: false)
  end
  let(:inbox) { whatsapp_channel.inbox }

  describe '#perform' do
    it 'creates an incoming message from MESSAGES_UPSERT' do
      params = {
        event: 'messages.upsert',
        data: {
          key: {
            remoteJid: '5511888777666@s.whatsapp.net',
            fromMe: false,
            id: 'EVO_IN_1'
          },
          pushName: 'Alice',
          message: {
            conversation: 'Oi pelo Evolution'
          }
        }
      }

      expect do
        described_class.new(inbox: inbox, params: params).perform
      end.to change(Message, :count).by(1)

      message = Message.find_by(source_id: 'EVO_IN_1')
      expect(message.content).to eq('Oi pelo Evolution')
      expect(message.message_type).to eq('incoming')
      expect(message.sender.name).to eq('Alice')
    end

    it 'updates message status from MESSAGES_UPDATE' do
      contact = create(:contact, account: inbox.account, phone_number: '+5511888777666')
      contact_inbox = create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5511888777666')
      conversation = create(:conversation, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
      message = create(:message, conversation: conversation, inbox: inbox, source_id: 'EVO_OUT_1',
                                 message_type: :outgoing, status: :sent)

      params = {
        event: 'messages.update',
        data: {
          key: { id: 'EVO_OUT_1' },
          status: 'READ'
        }
      }

      described_class.new(inbox: inbox, params: params).perform
      expect(message.reload.status).to eq('read')
    end

    it 'updates connection status' do
      params = {
        event: 'connection.update',
        data: { state: 'open' }
      }

      described_class.new(inbox: inbox, params: params).perform
      expect(whatsapp_channel.reload.provider_config['connection_status']).to eq('open')
    end

    it 'creates a group contact from GROUPS_UPSERT' do
      params = {
        event: 'groups.upsert',
        data: {
          id: '120363123456789012@g.us',
          subject: 'Equipe TDP'
        }
      }

      described_class.new(inbox: inbox, params: params).perform
      contact = inbox.account.contacts.find_by(identifier: 'EV.120363123456789012')
      expect(contact).to be_present
      expect(contact.name).to eq('Equipe TDP')
      expect(contact.additional_attributes['evolution_group']).to be(true)
    end

    it 'creates an activity message for CALL events' do
      params = {
        event: 'call',
        data: {
          from: '5511888777666@s.whatsapp.net',
          status: 'offer'
        }
      }

      expect do
        described_class.new(inbox: inbox, params: params).perform
      end.to change(Message, :count).by(1)

      expect(Message.last.message_type).to eq('activity')
    end

    it 'handles contacts.upsert when data is an array' do
      params = {
        event: 'contacts.upsert',
        data: [
          {
            remoteJid: '5511888777666@s.whatsapp.net',
            pushName: 'Bob'
          }
        ]
      }

      expect do
        described_class.new(inbox: inbox, params: params).perform
      end.to change(ContactInbox, :count).by(1)

      expect(inbox.contact_inboxes.find_by(source_id: '5511888777666').contact.name).to eq('Bob')
    end

    it 'resolves @lid senders using remoteJidAlt' do
      params = {
        event: 'messages.upsert',
        data: {
          key: {
            remoteJid: '268233793904672@lid',
            remoteJidAlt: '5511933579244@s.whatsapp.net',
            fromMe: false,
            id: 'EVO_LID_1'
          },
          pushName: 'Lucas',
          message: { conversation: 'Olá' }
        }
      }

      described_class.new(inbox: inbox, params: params).perform

      message = Message.find_by(source_id: 'EVO_LID_1')
      expect(message.content).to eq('Olá')
      expect(inbox.contact_inboxes.find_by(source_id: '5511933579244')).to be_present
    end
  end
end
