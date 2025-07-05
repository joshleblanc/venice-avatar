class FetchImageStylesJob < ApplicationJob
  def perform(user)
    return unless user.venice_key.present?

    image_api = VeniceClient::ImageApi.new(user.api_client)
    image_api.image_styles_get.data
  end
end
