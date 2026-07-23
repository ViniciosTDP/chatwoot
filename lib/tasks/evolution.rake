# frozen_string_literal: true

namespace :evolution do
  desc 'Re-apply Evolution webhooks with base64 media enabled for all evolution_api channels'
  task reapply_webhooks: :environment do
    channels = Channel::Whatsapp.where(provider: 'evolution_api')
    puts "Re-applying Evolution webhooks for #{channels.count} channel(s)..."

    channels.find_each do |channel|
      begin
        channel.evolution_instance_service.set_webhook!
        inbox = channel.inbox
        instance = channel.provider_config['instance_name']
        puts "OK inbox=#{inbox&.id} instance=#{instance}"
      rescue StandardError => e
        puts "FAIL channel=#{channel.id}: #{e.message}"
      end
    end
  end
end
