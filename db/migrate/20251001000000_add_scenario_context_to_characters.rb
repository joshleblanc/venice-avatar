class AddScenarioContextToCharacters < ActiveRecord::Migration[8.0]
  def change
    add_column :characters, :scenario_context, :text
  end
end