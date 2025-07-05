class AddEmbeddingsToCharacters < ActiveRecord::Migration[8.0]
  def change
    add_column :characters, :embedding, :binary
  end
end
