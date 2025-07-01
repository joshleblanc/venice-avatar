class Message < ApplicationRecord
  belongs_to :conversation

  validates :content, presence: true
  validates :role, presence: true, inclusion: { in: %w[user assistant] }

  scope :user_messages, -> { where(role: "user") }
  scope :assistant_messages, -> { where(role: "assistant") }
  scope :recent, -> { order(created_at: :desc) }

  # Parse message content to separate clean text from action descriptions
  def parsed_content
    @parsed_content ||= parse_message_content
  end

  # Get only the clean text without action descriptions
  def clean_text
    parsed_content[:clean_text]
  end

  # Get only the action descriptions and internal thoughts
  def actions_and_thoughts
    parsed_content[:actions_and_thoughts]
  end

  # Check if message has any action descriptions or internal thoughts
  def has_actions_or_thoughts?
    actions_and_thoughts.any?
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
    return { clean_text: content, actions_and_thoughts: [] } if content.blank?

    clean_text = content.dup
    actions_and_thoughts = []

    # Extract parenthetical actions like (blushes furiously)
    clean_text.gsub!(/\(([^)]+)\)/) do |match|
      actions_and_thoughts << { type: "action", text: $1.strip }
      "" # Remove from clean text
    end

    # Extract bold actions like **looks sternly**
    clean_text.gsub!(/\*\*([^*]+)\*\*/) do |match|
      actions_and_thoughts << { type: "action", text: $1.strip }
      "" # Remove from clean text
    end

    # Extract italic thoughts like *thinks to themselves*
    clean_text.gsub!(/\*([^*]+)\*/) do |match|
      actions_and_thoughts << { type: "thought", text: $1.strip }
      "" # Remove from clean text
    end

    # Extracts square bracket actions like [blushes furiously]
    clean_text.gsub!(/\[([^\]]+)\]/) do |match|
      actions_and_thoughts << { type: "action", text: $1.strip }
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
