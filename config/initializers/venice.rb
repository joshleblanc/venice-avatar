VeniceClient.configure do |config|
  config.access_token = Rails.application.credentials.dig(:venice, :api_key)
  config.debugging = false #Rails.env.development?
end
