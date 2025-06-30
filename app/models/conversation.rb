class Conversation < ApplicationRecord
  belongs_to :character
  has_many :messages, dependent: :destroy
  has_many :character_states, dependent: :destroy
  has_one :current_character_state, -> { order(created_at: :desc) }, class_name: 'CharacterState'

  validates :character_id, presence: true

  def current_background
    current_character_state&.background_prompt || generate_initial_background
  end

  def current_character_appearance
    current_character_state&.appearance_description || generate_initial_appearance
  end

  private

  def generate_initial_background
    "A cozy indoor setting with warm lighting, suitable for conversation"
  end

  def generate_initial_appearance
    character.description || "A friendly character ready for conversation"
  end
end
