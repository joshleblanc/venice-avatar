class GenerateImageJob < ApplicationJob
  def perform(user, prompt, opts = {})
    return unless user.venice_key.present?

    venice_client = VeniceClient::ImageApi.new
    venice_client.api_client.config.access_token = user.venice_key

    response = venice_client.generate_image({
      body: {
        model: user.preferred_image_model || "venice-uncensored",
        prompt: prompt,
        safe_mode: false,
        format: "png",
        style_preset: user.preferred_image_style || "Anime",
        seed: 123871273,
        **opts,
      },
    })

    response.images.first
  end
end
