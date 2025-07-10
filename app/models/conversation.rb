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

  def scene_prompt_diff
    return nil if scene_prompt_histories.count < 2
    
    latest_two = scene_prompt_histories.order(created_at: :desc).limit(2)
    return nil if latest_two.count < 2
    
    old_prompt = latest_two.second.prompt
    new_prompt = latest_two.first.prompt
    
    # Simple word-based diff
    old_words = old_prompt.split(/\s+/)
    new_words = new_prompt.split(/\s+/)
    
    diff = {
      old_prompt: old_prompt,
      new_prompt: new_prompt,
      old_created_at: latest_two.second.created_at,
      new_created_at: latest_two.first.created_at,
      old_trigger: latest_two.second.trigger,
      new_trigger: latest_two.first.trigger,
      changes: calculate_word_diff(old_words, new_words)
    }
    
    diff
  end

  private

  def calculate_word_diff(old_words, new_words)
    # Simple implementation - find added and removed words
    old_set = old_words.map(&:downcase).to_set
    new_set = new_words.map(&:downcase).to_set
    
    {
      added: (new_set - old_set).to_a,
      removed: (old_set - new_set).to_a,
      word_count_change: new_words.length - old_words.length
    }
  end
end
