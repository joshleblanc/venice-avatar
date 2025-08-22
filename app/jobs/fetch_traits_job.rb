class FetchTraitsJob < ApplicationJob
  def perform(user, type)
    Rails.cache.fetch("venice_model_traits/#{type}", expires_in: 1.hour) do 
      return unless user.venice_key.present?

      traits_api = VeniceClient::ModelsApi.new(user.api_client)

      traits_api.list_model_traits(type: type).data
    end
  end
end