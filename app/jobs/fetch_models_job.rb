class FetchModelsJob < ApplicationJob
  def perform(user, type)
    Rails.cache.fetch("venice_models/#{type}", expires_in: 1.hour) do 
      return unless user.venice_key.present?

      models_api = VeniceClient::ModelsApi.new(user.api_client)

      models_api.list_models(type: type).data.reject { _1.model_spec.traits.empty? }
    end
  end
end