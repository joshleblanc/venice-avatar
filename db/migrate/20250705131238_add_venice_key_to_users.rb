class AddVeniceKeyToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :venice_key, :string
  end
end
