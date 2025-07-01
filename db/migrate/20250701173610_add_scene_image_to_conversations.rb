class AddSceneImageToConversations < ActiveRecord::Migration[8.0]
  def change
    # Scene images will now be stored directly on conversations
    # This allows us to remove the character_states dependency
    # Active Storage will handle the attachment automatically
  end
end
