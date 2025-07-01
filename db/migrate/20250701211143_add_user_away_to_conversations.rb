class AddUserAwayToConversations < ActiveRecord::Migration[8.0]
  def change
    add_column :conversations, :user_away, :boolean, default: false, null: false
    add_index :conversations, :user_away
  end
end
