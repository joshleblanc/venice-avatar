class AddDetailedBackgroundInfoToCharacterStates < ActiveRecord::Migration[8.0]
  def change
    add_column :character_states, :detailed_background_info, :json
  end
end
