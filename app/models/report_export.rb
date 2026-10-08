# == Schema Information
#
# Table name: report_exports
#
#  id           :bigint           not null, primary key
#  error_code   :string
#  expires_at   :datetime         not null
#  filters      :jsonb            not null
#  processed_at :datetime
#  report_type  :string           not null
#  status       :string           default("pending"), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#  user_id      :bigint           not null
#
# Indexes
#
#  index_report_exports_on_account_id                             (account_id)
#  index_report_exports_on_account_id_and_user_id_and_created_at  (account_id,user_id,created_at)
#  index_report_exports_on_expires_at                             (expires_at)
#  index_report_exports_on_user_id                                (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (user_id => users.id)
#
class ReportExport < ApplicationRecord
  TYPES = %w[conversation agent label inbox team csat sla].freeze
  MAX_ROWS = 5000

  belongs_to :account
  belongs_to :user
  has_one_attached :document

  validates :report_type, inclusion: { in: TYPES }
  validates :expires_at, presence: true
  enum :status, { pending: 'pending', processing: 'processing', completed: 'completed', failed: 'failed' }

  scope :available, -> { where('expires_at > ?', Time.current) }

  def permitted?
    membership = account.account_users.find_by(user_id: user_id)
    return false unless account.active? && membership && account.feature_enabled?('reports')

    context = { account: account, user: user, account_user: membership }
    return CsatSurveyResponsePolicy.new(context, CsatSurveyResponse).download? if report_type == 'csat'
    return ChatwootApp.enterprise? && membership.administrator? if report_type == 'sla'

    ReportPolicy.new(context, :report).view?
  end
end
