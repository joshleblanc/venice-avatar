class FetchBalancesJob < ApplicationJob
  def perform(user)
    return unless user.venice_key.present?

    venice_client = VeniceClient::APIKeysApi.new(user.api_client)
    response = venice_client.get_api_key_rate_limits

    response.data
  end
end
