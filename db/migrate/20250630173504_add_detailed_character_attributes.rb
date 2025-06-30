class AddDetailedCharacterAttributes < ActiveRecord::Migration[8.0]
  def change
    add_column :character_states, :base_character_prompt, :text
    add_column :character_states, :physical_features, :json
    add_column :character_states, :hair_details, :json
    add_column :character_states, :eye_details, :json
    add_column :character_states, :body_type, :string
    add_column :character_states, :skin_tone, :string
    add_column :character_states, :distinctive_features, :json
    add_column :character_states, :default_outfit, :json
    add_column :character_states, :pose_style, :string
    add_column :character_states, :art_style_notes, :text
  end
end
