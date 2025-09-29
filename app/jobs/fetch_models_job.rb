class FetchModelsJob < ApplicationJob
  # Accepts an Account
  def perform(user, type)
    Rails.cache.fetch("venice_models/#{type}", expires_in: 1.hour) do
      client = user.api_client
      return unless client

      models_api = VeniceClient::ModelsApi.new(client)
      models_api.list_models(type: type).data
    end
  end
end
