class FetchBalancesJob < ApplicationJob
  # Accepts an Account and uses its effective Venice key (owner for personal accounts)
  def perform(account)
    client = account.api_client
    return unless client

    venice_client = VeniceClient::APIKeysApi.new(client)
    response = venice_client.get_api_key_rate_limits

    response.data
  end
end
