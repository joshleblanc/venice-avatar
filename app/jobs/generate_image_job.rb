class GenerateImageJob < ApplicationJob
  def perform(user, prompt, opts = {})
    client = user.api_client
    return unless client

    venice_client = VeniceClient::ImageApi.new(client)

    style = user.image_style

    # Use the user's image model method which handles fallback logic
    model = user.image_model

    options = {
      model: model,
      prompt: prompt.first(user.prompt_limit),
      safe_mode: user.safe_mode?,
      format: "png",
      **opts
    }
    # Respect explicit style in opts if provided; otherwise fall back to user's image_style
    Rails.logger.debug "Generating image pre: #{options}"
    if opts.key?(:style_preset)
      options[:style_preset] = opts[:style_preset].presence
    elsif style.present?
      options[:style_preset] = style
    end
    options.compact!
    Rails.logger.debug "Generating image: #{options}"

    response = venice_client.generate_image({
      generate_image_request: options
    })

    response.images.first
  end
end
