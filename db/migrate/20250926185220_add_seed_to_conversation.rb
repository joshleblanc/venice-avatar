class AddSeedToConversation < ActiveRecord::Migration[8.0]
  def change
    add_column :conversations, :seed, :integer
  end
end
