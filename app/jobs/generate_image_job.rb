class GenerateImageJob < ApplicationJob
  def perform(user, prompt, opts = {})
    return unless user.venice_key.present?

    venice_client = VeniceClient::ImageApi.new(user.api_client)

    response = venice_client.generate_image({
      generate_image_request: {
        model: user.preferred_image_model || "hidream",
        prompt: prompt.first(user.prompt_limit),
        safe_mode: user.safe_mode,
        format: "png",
        style_preset: user.image_style,
        seed: 123871273,
        **opts,
      },
    })

    response.images.first
  end
end
