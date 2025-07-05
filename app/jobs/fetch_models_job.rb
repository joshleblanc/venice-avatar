class FetchModelsJob < ApplicationJob
  def perform(user, type)
    return unless user.venice_key.present?

    models_api = VeniceClient::ModelsApi.new(user.api_client)

    models_api.list_models(type: type).data
  end
end
