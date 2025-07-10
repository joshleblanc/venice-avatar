class Conversation < ApplicationRecord
  broadcasts_refreshes

  belongs_to :character
  belongs_to :user
  has_many :messages, dependent: :destroy
  has_many :scene_prompt_histories, dependent: :destroy

  # Scene images are now stored directly on conversations
  has_one_attached :scene_image

  validates :character_id, presence: true

  def current_scene_prompt
    metadata&.dig("current_scene_prompt") || generate_initial_scene_prompt
  end

  def last_scene_image
    # Scene images are now stored directly on the conversation
    scene_image if scene_image.attached?
  end

  def generate_initial_scene_prompt
    prompt_service = AiPromptGenerationService.new(self)
    prompt_service.generate_initial_scene_prompt
  end

  private
end
