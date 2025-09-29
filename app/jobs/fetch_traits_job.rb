class FetchTraitsJob < ApplicationJob
  # Accepts an Account
  def perform(account, type)
    Rails.cache.fetch("venice_model_traits/#{type}", expires_in: 1.hour) do
      client = account.api_client
      return unless client

      traits_api = VeniceClient::ModelsApi.new(client)
      traits_api.list_model_traits(type: type).data
    end
  end
end
