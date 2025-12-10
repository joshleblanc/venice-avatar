class CreateVideoGenerations < ActiveRecord::Migration[8.0]
  def change
    create_table :video_generations do |t|
      t.references :conversation, null: false, foreign_key: true
      t.string :queue_id
      t.string :model
      t.string :status, default: "pending"
      t.text :prompt
      t.text :error
      t.string :duration, default: "5s"
      t.string :resolution, default: "720p"
      t.integer :average_execution_time
      t.integer :execution_duration

      t.timestamps
    end

    add_index :video_generations, :queue_id
    add_index :video_generations, :status
  end
end
