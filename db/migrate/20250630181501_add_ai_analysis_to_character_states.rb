class AddAiAnalysisToCharacterStates < ActiveRecord::Migration[8.0]
  def change
    add_column :character_states, :ai_analysis_summary, :text
    add_column :character_states, :mood_intensity, :integer
    add_column :character_states, :context_significance, :integer
  end
end
