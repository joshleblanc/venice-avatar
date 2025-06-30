class CreateMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.text :content, null: false
      t.string :role, null: false
      t.json :metadata

      t.timestamps
    end

    add_index :messages, :role
    add_index :messages, :created_at
  end
end
