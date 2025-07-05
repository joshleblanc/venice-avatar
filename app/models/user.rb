class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  def obfuscated_venice_key
    return "" if venice_key.blank?

    (venice_key.length - 4).times.map { "*" }.join + venice_key.last(4)
  end
end
