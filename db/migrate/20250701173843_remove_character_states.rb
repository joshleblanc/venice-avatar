class RemoveCharacterStates < ActiveRecord::Migration[8.0]
  def change
    # Remove character_states table since we've moved to conversation-based scene prompts
    # Scene images are now stored directly on conversations
    # Scene prompts are stored in conversation metadata
    drop_table :character_states do |t|
      t.integer "conversation_id", null: false
      t.string "location"
      t.text "appearance_description"
      t.string "expression"
      t.json "clothing_details"
      t.json "injury_details"
      t.json "appearance_details"
      t.text "background_prompt"
      t.string "background_image_url"
      t.string "character_image_url"
      t.text "message_context"
      t.string "triggered_by_role"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.text "base_character_prompt"
      t.json "physical_features"
      t.json "hair_details"
      t.json "eye_details"
      t.string "body_type"
      t.string "skin_tone"
      t.json "distinctive_features"
      t.json "default_outfit"
      t.string "pose_style"
      t.text "art_style_notes"
      t.boolean "character_image_generating"
      t.boolean "background_image_generating"
      t.text "ai_analysis_summary"
      t.integer "mood_intensity"
      t.integer "context_significance"
      t.json "detailed_background_info"
      t.json "unified_state_data"
      t.index ["conversation_id"], name: "index_character_states_on_conversation_id"
      t.index ["created_at"], name: "index_character_states_on_created_at"
      t.index ["unified_state_data"], name: "index_character_states_on_unified_state_data"
    end
  end
end
