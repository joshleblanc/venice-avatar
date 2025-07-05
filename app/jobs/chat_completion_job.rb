class ChatCompletionJob < ApplicationJob
  def perform(user, messages = [], opts = {})
    return unless user.venice_key.present?

    venice_client = VeniceClient::ChatApi.new
    venice_client.api_client.config.access_token = user.venice_key

    response = venice_client.create_chat_completion({
      body: {
        model: user.preferred_text_model || "venice-uncensored",
        messages: messages,
        **opts,
      },
    })

    response.choices.first[:message][:content].strip
  end
end
