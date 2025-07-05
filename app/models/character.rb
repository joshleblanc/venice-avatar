class Character < ApplicationRecord
  broadcasts_refreshes

  has_neighbors :embedding

  acts_as_taggable_on :tags

  validates :slug, presence: true, uniqueness: true, unless: :generating?
  validates :name, presence: true, unless: :generating?
  validates :description, presence: true, unless: :generating?

  belongs_to :user, required: false

  scope :user_created, -> { where(user_created: true) }
  scope :venice_created, -> { where(user_created: false) }

  def user_created?
    user_created == true
  end

  def venice_created?
    !user_created?
  end

  def personality_ready?
    return true if venice_created?
    character_instructions.present?
  end
end
