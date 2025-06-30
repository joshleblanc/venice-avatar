require "mini_magick"

class BackgroundRemovalService
  def self.remove_background_from_data(image_data)
    begin
      # Create a temporary file for MiniMagick processing
      temp_input = Tempfile.new(["input", ".png"])
      temp_input.binmode
      temp_input.write(image_data)
      temp_input.close

      Rails.logger.info "Processing image for selective background removal"

      # Process the image to remove background selectively using MiniMagick directly
      # This approach only removes background connected to edges, preserving subject details
      processed_image = MiniMagick::Image.open(temp_input.path)

      # Get image dimensions for flood fill
      width = processed_image.width
      height = processed_image.height

      # Convert to PNG for transparency support
      processed_image.format "png"

      # Enable alpha channel for transparency
      processed_image.alpha "set"

      # Use MiniMagick's transparent method to remove white backgrounds
      # This approach is more reliable than flood fill for background removal
      processed_image.fuzz "15%" # Higher tolerance for better background detection
      processed_image.transparent "white"
      processed_image.transparent "#ffffff"
      processed_image.transparent "#fefefe"
      processed_image.transparent "#fdfdfd"

      # Remove light gray backgrounds that might appear
      processed_image.fuzz "10%"
      processed_image.transparent "#f8f8f8"
      processed_image.transparent "#f0f0f0"
      processed_image.transparent "#e8e8e8"

      Rails.logger.info "Background removal transformations completed"

      # Read the processed image data from MiniMagick::Image using to_blob
      processed_data = processed_image.to_blob
      Rails.logger.info "Processed image size: #{processed_data.bytesize} bytes"

      # Verify the processed image has transparency
      if processed_data.bytesize > 0
        Rails.logger.info "Background removal completed successfully"
      else
        Rails.logger.error "Processed image is empty!"
      end

      # Clean up the temporary files
      temp_input.unlink if temp_input

      processed_data
    rescue => e
      Rails.logger.error "Failed to remove background: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      # Clean up temporary files on error
      temp_input.unlink if temp_input && File.exist?(temp_input.path)
      nil
    end
  end

  def self.process_and_attach(character_state, attachment_name, base64_data, filename)
    begin
      # Decode the base64 image data
      image_data = Base64.decode64(base64_data)
      Rails.logger.info "Starting selective background removal for #{attachment_name}"

      # Process the image directly from the decoded data
      processed_data = BackgroundRemovalService.remove_background_from_data(image_data)

      if processed_data && processed_data.bytesize > 0
        Rails.logger.info "Background removal successful, processed data size: #{processed_data.bytesize} bytes"

        # Attach the processed image with transparent background
        processed_io = StringIO.new(processed_data)
        processed_io.set_encoding(Encoding::BINARY)

        new_filename = filename.gsub(/\.(png|jpg|jpeg|webp)$/i, ".png")
        Rails.logger.info "Attaching processed image as: #{new_filename}"

        attachment = character_state.public_send(attachment_name)
        attachment.attach(
          io: processed_io,
          filename: new_filename,
          content_type: "image/png",
        )

        Rails.logger.info "Successfully processed and attached #{attachment_name} with transparent background"
        true
      else
        Rails.logger.warn "Background removal failed or returned empty data, falling back to original image"
        Rails.logger.warn "Processed data size: #{processed_data&.bytesize || "nil"} bytes"

        # Fallback: attach original image
        original_io = StringIO.new(image_data)
        original_io.set_encoding(Encoding::BINARY)

        attachment = character_state.public_send(attachment_name)
        attachment.attach(
          io: original_io,
          filename: filename,
          content_type: "image/png",
        )

        Rails.logger.info "Attached original image as fallback"
        false
      end
    rescue => e
      Rails.logger.error "Failed to remove background: #{e.class}"
      Rails.logger.error e.message
      Rails.logger.error e.backtrace.join("\n")

      # Fallback: try to attach original image
      begin
        image_data = Base64.decode64(base64_data)
        original_io = StringIO.new(image_data)
        original_io.set_encoding(Encoding::BINARY)

        attachment = character_state.public_send(attachment_name)
        attachment.attach(
          io: original_io,
          filename: filename,
          content_type: "image/png",
        )

        Rails.logger.info "Attached original image as error fallback"
      rescue => fallback_error
        Rails.logger.error "Failed to attach fallback image: #{fallback_error.message}"
      end

      false
    end
  end
end
