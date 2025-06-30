class CreateConversations < ActiveRecord::Migration[8.0]
  def change
    create_table :conversations do |t|
      t.references :character, null: false, foreign_key: true
      t.string :title
      t.text :summary

      t.timestamps
    end

    add_index :conversations, :updated_at
  end
end
