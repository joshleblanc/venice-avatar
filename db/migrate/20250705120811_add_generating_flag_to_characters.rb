class AddGeneratingFlagToCharacters < ActiveRecord::Migration[8.0]
  def change
    add_column :characters, :generating, :boolean, default: false
  end
end
