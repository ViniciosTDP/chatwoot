class CreateReportExports < ActiveRecord::Migration[7.1]
  def change
    create_table :report_exports do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :report_type, null: false
      t.jsonb :filters, null: false, default: {}
      t.string :status, null: false, default: 'pending'
      t.string :error_code
      t.datetime :processed_at
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :report_exports, [:account_id, :user_id, :created_at]
    add_index :report_exports, :expires_at
  end
end
