class Conversation < ApplicationRecord
  broadcasts_refreshes

  belongs_to :character
  has_many :messages, dependent: :destroy
  has_many :character_states, dependent: :destroy
  has_one :current_character_state, -> { order(created_at: :desc) }, class_name: "CharacterState"

  validates :character_id, presence: true

  def current_background
    current_character_state&.background_prompt || generate_initial_background
  end

  def current_character_appearance
    current_character_state&.appearance_description || generate_initial_appearance
  end

  def last_character_image
    character_states.joins(:character_image_attachment)
                   .order(created_at: :desc)
                   .first&.character_image
  end

  def last_background_image
    character_states.joins(:background_image_attachment)
                   .order(created_at: :desc)
                   .first&.background_image
  end

  private

  def generate_initial_background
    "A cozy indoor setting with warm lighting, suitable for conversation"
  end

  def generate_initial_appearance
    character.description || "A friendly character ready for conversation"
  end
end
