class AddSafeModeToProfile < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :safe_mode, :boolean, default: true
  end
end
