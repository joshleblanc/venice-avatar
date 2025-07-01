class AddGeneratingReplyToConversations < ActiveRecord::Migration[8.0]
  def change
    add_column :conversations, :generating_reply, :boolean
  end
end
