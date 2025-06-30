class CreateCharacterStates < ActiveRecord::Migration[8.0]
  def change
    create_table :character_states do |t|
      t.references :conversation, null: false, foreign_key: true
      t.string :location
      t.text :appearance_description
      t.string :expression
      t.json :clothing_details
      t.json :injury_details
      t.json :appearance_details
      t.text :background_prompt
      t.string :background_image_url
      t.string :character_image_url
      t.text :message_context
      t.string :triggered_by_role

      t.timestamps
    end

    add_index :character_states, :created_at
  end
end
