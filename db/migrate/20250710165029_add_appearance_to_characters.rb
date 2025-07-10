class AddAppearanceToCharacters < ActiveRecord::Migration[8.0]
  def change
    add_column :characters, :appearance, :text
  end
end
