class AddFollowUpFieldsToMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :messages, :has_pending_followup, :boolean
    add_column :messages, :followup_scheduled_at, :datetime
    add_column :messages, :followup_context, :text
    add_column :messages, :followup_reason, :string
  end
end
