class AddPreferencesToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :timezone, :string
    add_column :users, :preferred_image_model, :string, default: "flux-dev-uncensored-11"
    add_column :users, :preferred_text_model, :string, default: "venice-uncensored"
  end
end
