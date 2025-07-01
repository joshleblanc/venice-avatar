class AddUnifiedStateDataToCharacterStates < ActiveRecord::Migration[7.0]
  def change
    add_column :character_states, :unified_state_data, :json
    add_index :character_states, :unified_state_data, using: :gin
  end
end
