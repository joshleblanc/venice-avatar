class Character < ApplicationRecord
  acts_as_taggable_on :tags

  validates :slug, presence: true, uniqueness: true
end
