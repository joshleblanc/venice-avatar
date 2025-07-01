class AddSceneGenerationToConversations < ActiveRecord::Migration[8.0]
  def change
    add_column :conversations, :scene_generating, :boolean
  end
end
