class FetchImageStylesJob < ApplicationJob
  # Accepts an Account
  def perform(account)
    Rails.cache.fetch("venice_image_styles", expires_in: 1.hour) do
      client = account.api_client
      return unless client

      image_api = VeniceClient::ImageApi.new(client)
      image_api.image_styles_get.data
    end
  end
end
