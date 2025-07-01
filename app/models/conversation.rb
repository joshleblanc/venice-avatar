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

  def last_scene_image
    # Try to get the most recent scene image first
    scene_state = character_states.joins(:scene_image_attachment)
      .order(created_at: :desc)
      .first
    return scene_state.scene_image if scene_state
  end

  private

  def generate_initial_background
    "A cozy indoor setting with warm lighting, suitable for conversation"
  end

  def generate_initial_appearance
    character.description || "A friendly character ready for conversation"
  end
end
