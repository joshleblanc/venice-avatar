class CreateScenePromptHistories < ActiveRecord::Migration[8.0]
  def change
    create_table :scene_prompt_histories do |t|
      t.references :conversation, null: false, foreign_key: true
      t.text :prompt, null: false
      t.string :trigger, null: false
      t.integer :character_count, null: false

      t.timestamps
    end
    
    add_index :scene_prompt_histories, [:conversation_id, :created_at]
    add_index :scene_prompt_histories, :trigger
  end
end
