class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, if: -> { new_record? || !password.nil? }

  validate :venice_key_must_be_valid

  def venice_key_must_be_valid
    if balances.nil?
      self.venice_key_valid = false
      errors.add(:venice_key, "is invalid")
    else
      self.venice_key_valid = true
    end
  end

  def prompt_limit
    if image_model.include?("flux")
      2048
    else
      1500
    end
  end

  def balances
    Rails.cache.fetch("user/#{id}/#{venice_key}/balances", expires_in: 1.hour) do
      balances = FetchBalancesJob.perform_now(self)
      balances.is_a?(VeniceClient::ApiError) ? nil : balances
    end
  end

  def obfuscated_venice_key
    return "" if venice_key.blank?

    (venice_key.length - 4).times.map { "*" }.join + venice_key.last(4)
  end

  def image_style 
    if preferred_image_style.nil?
      "Anime"
    elsif preferred_image_style.blank?
      nil
    else
      preferred_image_style
    end
  end

  def text_model
    traits = FetchTraitsJob.perform_now(self, "text") || {}
    if preferred_text_model.present?
      # Allow storing either a trait key or a raw model id
      traits[preferred_text_model] || preferred_text_model
    else
      traits["default"]
    end
  end

  def image_model
    traits = FetchTraitsJob.perform_now(self, "image") || {}
    if preferred_image_model.present?
      traits[preferred_image_model] || preferred_image_model
    else
      traits["default"]
    end
  end

  def api_client
    return unless venice_key.present?
    config = VeniceClient::Configuration.new
    config.access_token = self.venice_key
    VeniceClient::ApiClient.new(config)
  end
end
