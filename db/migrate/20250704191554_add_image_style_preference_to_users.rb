class AddImageStylePreferenceToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :preferred_image_style, :string, default: "Anime"
  end
end
