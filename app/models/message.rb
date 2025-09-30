class Message < ApplicationRecord
  belongs_to :conversation
  belongs_to :user

  validates :content, presence: true
  validates :role, presence: true, inclusion: { in: %w[user assistant] }

  scope :user_messages, -> { where(role: "user") }
  scope :assistant_messages, -> { where(role: "assistant") }
  scope :recent, -> { order(created_at: :desc) }

  # Parse message content to separate clean text from action descriptions
  def parsed_content
    @parsed_content ||= parse_message_content
  end

  # Get formatted content with inline highlighting for actions/thoughts
  def formatted_content
    return content if content.blank?

    formatted = content.dup

    # Wrap different patterns with span tags for styling
    # Single asterisks for thoughts (green)
    formatted.gsub!(/\*([^*]+)\*/, '<span class="text-green-600 italic">\1</span>')

    # Double asterisks for actions (amber/yellow)
    formatted.gsub!(/\*\*([^*]+)\*\*/, '<span class="text-amber-600 font-medium">\1</span>')

    # Square brackets for actions (blue)
    formatted.gsub!(/\[([^\]]+)\]/, '<span class="text-blue-600 font-medium">\1</span>')

    # Parentheses for actions (purple)
    formatted.gsub!(/\(([^)]+)\)/, '<span class="text-purple-600 italic">\1</span>')

    formatted
  end

  # Get the full content for AI analysis (includes everything)
  def full_content_for_ai
    content
  end

  # Check if this is an auto-generated message (like "brb")
  def auto_generated?
    metadata.is_a?(Hash) && metadata["auto_generated"] == true
  end

  # Get the reason for auto-generation if available
  def auto_generation_reason
    metadata.is_a?(Hash) ? metadata["reason"] : nil
  end

  private

  def parse_message_content
    return { clean_text: "", actions_and_thoughts: [] } if content.blank?

    clean_text = content.dup
    actions_and_thoughts = []

    # Extract parenthetical actions like (blushes furiously)
    clean_text.gsub!(/\(([^)]*)\)/) do |match|
      text = $1.strip
      actions_and_thoughts << { type: "action", text: text } unless text.empty?
      "" # Remove from clean text
    end

    # Extract bold actions like **looks sternly**
    clean_text.gsub!(/\*\*([^*]*)\*\*/) do |match|
      text = $1.strip
      actions_and_thoughts << { type: "action", text: text } unless text.empty?
      "" # Remove from clean text
    end

    # Extract italic thoughts like *thinks to themselves*
    clean_text.gsub!(/\*([^*]*)\*/) do |match|
      text = $1.strip
      actions_and_thoughts << { type: "thought", text: text } unless text.empty?
      "" # Remove from clean text
    end

    # Extracts square bracket actions like [blushes furiously]
    clean_text.gsub!(/\[([^\]]*)\]/) do |match|
      text = $1.strip
      actions_and_thoughts << { type: "action", text: text } unless text.empty?
      "" # Remove from clean text
    end

    # Clean up extra whitespace
    clean_text = clean_text.gsub(/\s+/, " ").strip

    {
      clean_text: clean_text,
      actions_and_thoughts: actions_and_thoughts,
    }
  end
end
