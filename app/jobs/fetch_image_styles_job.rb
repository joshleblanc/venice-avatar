class FetchImageStylesJob < ApplicationJob
  def perform(user)
    return unless user.venice_key.present?

    image_api = VeniceClient::ImageApi.new
    image_api.api_client.config.access_token = user.venice_key

    image_api.image_styles_get.data
  end
end
