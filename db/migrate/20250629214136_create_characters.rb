class CreateCharacters < ActiveRecord::Migration[8.0]
  def change
    create_table :characters do |t|
      t.boolean :adult
      t.datetime :external_created_at
      t.text :description
      t.string :name
      t.string :share_url
      t.string :slug
      t.json :stats
      t.datetime :external_updated_at
      t.boolean :web_enabled

      t.timestamps
    end

    add_index :characters, :slug, unique: true
  end
end
