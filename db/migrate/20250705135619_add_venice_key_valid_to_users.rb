class AddVeniceKeyValidToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :venice_key_valid, :boolean
  end
end
