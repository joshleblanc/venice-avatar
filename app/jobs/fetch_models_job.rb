class FetchModelsJob < ApplicationJob
  def perform(user, type)
    return unless user.venice_key.present?

    models_api = VeniceClient::ModelsApi.new
    models_api.api_client.config.access_token = user.venice_key

    models_api.list_models(type: type).data
  end
end
