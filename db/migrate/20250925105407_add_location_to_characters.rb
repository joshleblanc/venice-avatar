class AddLocationToCharacters < ActiveRecord::Migration[8.0]
  def change
    add_column :characters, :location, :text
  end
end
