class ChatCompletionJob < ApplicationJob
  def perform(user, messages = [], opts = {}, model_override = nil)
    client =user.api_client
    return unless client

    opts[:venice_parameters] ||= VeniceClient::ChatCompletionRequestVeniceParameters.new
    opts[:venice_parameters].strip_thinking_response = true
    opts[:venice_parameters].disable_thinking = true

    # Use model_override directly if provided, otherwise fall back to traits default
    if model_override.present?
      # Check if the model exists in available models
      available_models = FetchModelsJob.perform_now(user, "text") || []
      if available_models.any? { |m| m.id == model_override }
        model = model_override
      else
        # Model not found, fall back to traits default
        Rails.logger.info "Model '#{model_override}' not available, falling back to default"
        traits = FetchTraitsJob.perform_now(user, "text") || {}
        model = traits["default"]
      end
    else
      # No model specified, use traits default
      traits = FetchTraitsJob.perform_now(user, "text") || {}
      model = traits["default"]
    end

    venice_client = VeniceClient::ChatApi.new(client)
    response = venice_client.create_chat_completion({
      chat_completion_request: {
        model: model,
        messages: messages,
        **opts
      }
    })

    response.choices.first.message
  end
end
