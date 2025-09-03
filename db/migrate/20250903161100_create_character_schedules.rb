class CreateCharacterSchedules < ActiveRecord::Migration[8.0]
  def change
    create_table :character_schedules do |t|
      t.references :character, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :schedule_type, null: false # daily, weekly, random, contextual
      t.json :trigger_conditions, null: false # conditions for when to trigger
      t.integer :priority, null: false, default: 5 # 1-10, higher = more important
      t.boolean :active, null: false, default: true
      t.json :metadata # additional configuration
      t.timestamps
    end
    
    add_index :character_schedules, [:character_id, :active]
    add_index :character_schedules, [:schedule_type, :active]
    add_index :character_schedules, :priority
  end
end