class Conversation < ApplicationRecord
  broadcasts_refreshes

  belongs_to :character
  belongs_to :user
  has_many :messages, dependent: :destroy
  has_many :scene_prompt_histories, dependent: :destroy

  # Scene images are now stored directly on conversations
  has_one_attached :scene_image

  validates :character_id, presence: true

  store_accessor :metadata, :appearance, :location

  def current_scene_prompt
    # Prefer stored metadata. If missing, use the prompt service's
    # non-blocking getter which enqueues background generation and
    # returns a lightweight fallback immediately (avoids blocking
    # the web request with synchronous AI calls).
    metadata&.dig("current_scene_prompt") || AiPromptGenerationService.new(self).get_current_scene_prompt
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
    return @scene_prompt_histories if @scene_prompt_histories

    if scene_prompt_histories.count < 2
      @scene_prompt_histories = nil
      return nil
    end


    latest_two = scene_prompt_histories.order(created_at: :desc).limit(2)
    if latest_two.count < 2
      @scene_prompt_histories = nil
      return nil
    end

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

    @scene_prompt_histories = diff
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
