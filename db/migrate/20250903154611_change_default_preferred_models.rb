class ChangeDefaultPreferredModels < ActiveRecord::Migration[8.0]
  def change
    change_column_default :users, :preferred_image_model, from: "hidream", to: "default"
    change_column_default :users, :preferred_text_model, from: "venice-uncensored", to: "default"
    
    # Update existing users who have the old default values
    User.where(preferred_image_model: "hidream").update_all(preferred_image_model: "default")
    User.where(preferred_text_model: "venice-uncensored").update_all(preferred_text_model: "default")
  end
end
