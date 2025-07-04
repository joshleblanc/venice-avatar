class AddUserCreatedFieldsToCharacters < ActiveRecord::Migration[8.0]
  def change
    add_column :characters, :user_created, :boolean, default: false
    add_column :characters, :character_instructions, :text
    
    add_index :characters, :user_created
  end
end
