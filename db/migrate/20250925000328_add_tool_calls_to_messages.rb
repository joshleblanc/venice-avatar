class AddToolCallsToMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :messages, :tool_calls, :jsonb
    change_column_null :messages, :content, true
  end
end
