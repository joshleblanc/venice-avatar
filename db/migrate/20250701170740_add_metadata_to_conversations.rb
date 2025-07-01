class AddMetadataToConversations < ActiveRecord::Migration[8.0]
  def change
    add_column :conversations, :metadata, :json
  end
end
