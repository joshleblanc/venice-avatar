class EditImageJob < ApplicationJob
  queue_as :default

  def perform(user, base64_image, edit_prompt)
    Rails.logger.info "Starting image edit job for user: #{user.id}"
    Rails.logger.info "Edit prompt: #{edit_prompt}"
    Rails.logger.info "Base64 image length: #{base64_image.length}"

    venice_client = VeniceClient::ImageApi.new(user.api_client)

    file = venice_client.edit_image({
      edit_image_request: {
        image: base64_image,
        prompt: edit_prompt,
      },
    })

    if file
      file
    else
      Rails.logger.error "No image data received from Venice image edit API"
      nil
    end
  rescue => e
    debugger
    Rails.logger.error "Image edit job failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    nil
  end
end
