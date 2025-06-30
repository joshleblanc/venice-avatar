class CharacterState < ApplicationRecord
  belongs_to :conversation

  # Active Storage attachments for generated images
  has_one_attached :character_image
  has_one_attached :background_image

  validates :conversation_id, presence: true

  # Character appearance tracking
  # JSON columns handle serialization automatically

  # Image URLs for generated content
  validates :background_image_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true }
  validates :character_image_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true }

  scope :recent, -> { order(created_at: :desc) }

  def appearance_changed?(previous_state)
    return true if previous_state.nil?
    
    appearance_description != previous_state.appearance_description ||
      expression != previous_state.expression ||
      clothing_details != previous_state.clothing_details ||
      injury_details != previous_state.injury_details
  end

  def location_changed?(previous_state)
    return true if previous_state.nil?
    
    location != previous_state.location ||
      background_prompt != previous_state.background_prompt
  end

  def needs_background_update?(previous_state)
    location_changed?(previous_state) || background_image_url.blank?
  end

  def needs_character_update?(previous_state)
    appearance_changed?(previous_state) || character_image_url.blank?
  end
end
