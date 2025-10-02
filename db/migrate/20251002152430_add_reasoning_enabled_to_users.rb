class AddReasoningEnabledToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :reasoning_enabled, :boolean, default: false, null: false
  end
end
