class ScenePromptHistory < ApplicationRecord
  belongs_to :conversation

  validates :prompt, presence: true
  validates :trigger, presence: true
  validates :character_count, presence: true, numericality: { greater_than: 0 }

  scope :ordered, -> { order(:created_at) }
  scope :by_trigger, ->(trigger) { where(trigger: trigger) }
  scope :recent, ->(limit = 10) { order(created_at: :desc).limit(limit) }

  before_validation :set_character_count

  private

  def set_character_count
    self.character_count = prompt&.length || 0
  end
end