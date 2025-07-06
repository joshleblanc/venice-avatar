module ApplicationHelper
  def format_message_content(content)
    return content if content.blank?

    # Convert text between single asterisks to italics
    # e.g., "Hello *waves* there!" becomes "Hello <em>waves</em> there!"
    formatted_content = content.gsub(/\*([^*]+)\*/) do |match|
      "<em style='color: purple;'>#{$1.strip}</em>"
    end

    # Return as HTML safe string so it renders properly
    formatted_content.html_safe
  end
end
