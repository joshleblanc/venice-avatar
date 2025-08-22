class FetchImageStylesJob < ApplicationJob
  def perform(user)
    Rails.cache.fetch("venice_image_styles", expires_in: 1.hour) do
      return unless user.venice_key.present?

      image_api = VeniceClient::ImageApi.new(user.api_client)
      image_api.image_styles_get.data
    end
  end
end
