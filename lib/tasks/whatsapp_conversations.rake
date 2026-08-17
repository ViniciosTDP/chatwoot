# Resolve extra open WhatsApp threads for the same contact+inbox.
#
# Keeps the conversation with the latest last_activity_at and moves messages
# from the other open duplicates onto it, then marks those as resolved.
#
#   ACCOUNT_ID=171 INBOX_ID=128 DRY_RUN=true bundle exec rake whatsapp:merge_duplicate_conversations
#   ACCOUNT_ID=171 INBOX_ID=128 bundle exec rake whatsapp:merge_duplicate_conversations
namespace :whatsapp do
  desc 'Merge extra open WhatsApp conversations that share the same contact_inbox'
  task merge_duplicate_conversations: :environment do
    account_id = ENV.fetch('ACCOUNT_ID')
    inbox_id = ENV['INBOX_ID']
    dry_run = ENV['DRY_RUN'].present?

    inboxes = Inbox.where(account_id: account_id, channel_type: 'Channel::Whatsapp')
    inboxes = inboxes.where(id: inbox_id) if inbox_id.present?

    merged = 0
    inboxes.find_each do |inbox|
      ContactInbox.where(inbox_id: inbox.id).find_each do |contact_inbox|
        opens = contact_inbox.conversations.open.order(last_activity_at: :desc)
        next if opens.size < 2

        keeper = opens.first
        extras = opens.offset(1)
        extras.each do |dup|
          message_count = dup.messages.count
          puts "contact_inbox=#{contact_inbox.id} keep=#{keeper.display_id} resolve=#{dup.display_id} messages=#{message_count}"
          next if dry_run

          dup.messages.update_all(conversation_id: keeper.id) # rubocop:disable Rails/SkipsModelValidations
          dup.resolved!
          merged += 1
        end
      end
    end

    puts dry_run ? "DRY_RUN complete (#{merged} would be merged)" : "Merged #{merged} duplicate conversation(s)"
  end
end
