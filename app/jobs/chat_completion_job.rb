class ChatCompletionJob < ApplicationJob
  def perform(user, messages = [], opts = {}, model_override = nil)
    return unless user.venice_key.present?

    opts[:venice_parameters] ||= VeniceClient::ChatCompletionRequestVeniceParameters.new
    opts[:venice_parameters].strip_thinking_response = true

    # Resolve model from trait if a trait key is provided
    if model_override.present?
      traits = FetchTraitsJob.perform_now(user, "text") || {}
      model = traits[model_override] || model_override
    else
      model = (FetchTraitsJob.perform_now(user, "text") || {})["default"]
    end

    venice_client = VeniceClient::ChatApi.new(user.api_client)
    response = venice_client.create_chat_completion({
      chat_completion_request: {
        model: model,
        messages: messages,
        **opts,
      },
    })

    response.choices.first.message.content.strip
  end
end
