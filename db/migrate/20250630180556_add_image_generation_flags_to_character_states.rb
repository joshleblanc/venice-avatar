class AddImageGenerationFlagsToCharacterStates < ActiveRecord::Migration[8.0]
  def change
    add_column :character_states, :character_image_generating, :boolean
    add_column :character_states, :background_image_generating, :boolean
  end
end
