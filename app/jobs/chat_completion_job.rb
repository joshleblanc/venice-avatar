class ChatCompletionJob < ApplicationJob
  def perform(user, messages = [], opts = {}, model_override = nil)
    return unless user.venice_key.present?

    opts[:venice_parameters] ||= VeniceClient::ChatCompletionRequestVeniceParameters.new
    opts[:venice_parameters].strip_thinking_response = true

    venice_client = VeniceClient::ChatApi.new(user.api_client)
    response = venice_client.create_chat_completion({
      chat_completion_request: {
        model: model_override || "venice-uncensored",
        messages: messages,
        **opts,
      },
    })

    response.choices.first.message.content.strip
  end
end
