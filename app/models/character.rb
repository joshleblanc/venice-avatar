class Character < ApplicationRecord
  acts_as_taggable_on :tags

  validates :slug, presence: true, uniqueness: true
  validates :name, presence: true
  validates :description, presence: true
  
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
