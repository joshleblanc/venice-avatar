class ChatCompletionJob < ApplicationJob
  def perform(user, messages = [], opts = {})
    venice_client = VeniceClient::ChatApi.new
    response = venice_client.create_chat_completion({
      body: {
        model: user.preferred_text_model || "venice-uncensored",
        messages: messages,
        max_completion_tokens: opts[:max_completion_tokens] || 500,
        temperature: opts[:temperature] || 0.5, # Higher temperature for more creativity
      },
    })

    response.choices.first[:message][:content].strip
  end
end
