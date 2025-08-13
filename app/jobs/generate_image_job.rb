class GenerateImageJob < ApplicationJob
  def perform(user, prompt, opts = {})
    return unless user.venice_key.present?

    venice_client = VeniceClient::ImageApi.new(user.api_client)

    style = user.image_style 

    options = {
      model: user.preferred_image_model || "hidream",
      prompt: prompt.first(user.prompt_limit),
      safe_mode: user.safe_mode,
      cfg_scale: 1,
      steps: 30,
      format: "png",
      seed: 123871273,
      **opts,
    }
    options[:style_preset] = style if style.present?
    
    response = venice_client.generate_image({
      generate_image_request: options,
    })

    response.images.first
  end
end
