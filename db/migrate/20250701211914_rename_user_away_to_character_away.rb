class RenameUserAwayToCharacterAway < ActiveRecord::Migration[8.0]
  def change
    rename_column :conversations, :user_away, :character_away
    rename_index :conversations, :index_conversations_on_user_away, :index_conversations_on_character_away
  end
end
