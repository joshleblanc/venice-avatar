# VideoGenerationService
#
# Handles video generation using the Venice Video API.
# Supports image-to-video generation from the current scene image.
#
class VideoGenerationService
  VIDEO_MODEL = "wan-2.5-preview-image-to-video".freeze
  DEFAULT_NEGATIVE_PROMPT = "low resolution, error, worst quality, low quality, defects".freeze
  MAX_PROMPT_LENGTH = 200

  def initialize(conversation)
    @conversation = conversation
    @user = conversation.user
    @character = conversation.character
  end

  # Get a price quote for video generation
  # @param duration [String] "5s" or "10s"
  # @param resolution [String] "480p", "720p", or "1080p"
  # @return [Hash] Quote information including price
  def quote(duration: "5s", resolution: "720p")
    return { error: "No scene image available" } unless @conversation.scene_image.attached?

    client = video_client
    return { error: "No API client available" } unless client

    image_data_url = scene_image_data_url
    prompt = generate_action_prompt

    begin
      response = client.quote_video({
        queue_video_request: VeniceClient::QueueVideoRequest.new(
          model: VIDEO_MODEL,
          prompt: prompt,
          negative_prompt: DEFAULT_NEGATIVE_PROMPT,
          # duration: duration,
          # resolution: resolution,
          aspect_ratio: "16:9",
          image_url: image_data_url,
          # audio: true
        )
      })

      { quote: response.quote }
    rescue VeniceClient::ApiError => e
      Rails.logger.error "Video quote failed: #{e.message}"
      { error: e.message }
    end
  end

  # Queue a new video generation request
  # @param duration [String] "5s" or "10s"
  # @param resolution [String] "480p", "720p", or "1080p"
  # @return [VideoGeneration] The video generation record
  def queue(duration: "5s", resolution: "720p")
    return nil unless @conversation.scene_image.attached?

    client = video_client
    return nil unless client

    image_data_url = scene_image_data_url
    prompt = generate_action_prompt

    # Create the video generation record
    video_generation = @conversation.video_generations.create!(
      status: VideoGeneration::PENDING,
      prompt: prompt,
      duration: duration,
      resolution: resolution,
      model: VIDEO_MODEL
    )

    begin
      response = client.queue_video({
        queue_video_request: VeniceClient::QueueVideoRequest.new(
          model: VIDEO_MODEL,
          prompt: prompt,
          negative_prompt: DEFAULT_NEGATIVE_PROMPT,
          duration: duration,
          resolution: resolution,
          image_url: image_data_url,
          # audio: true
        )
      })

      video_generation.update!(
        queue_id: response.queue_id,
        model: response.model,
        status: VideoGeneration::QUEUED
      )

      Rails.logger.info "Video queued successfully: #{response.queue_id}"
      video_generation
    rescue VeniceClient::ApiError => e
      Rails.logger.error "Video queue failed: #{e.message}"
      video_generation.update!(
        status: VideoGeneration::FAILED,
        error: e.message
      )
      video_generation
    end
  end

  # Retrieve the status or completed video
  # @param video_generation [VideoGeneration] The video generation record
  # @return [VideoGeneration] Updated video generation record
  def retrieve(video_generation)
    return video_generation unless video_generation.in_progress?

    client = video_client
    return video_generation unless client

    begin
      response, status_code, headers = client.retrieve_video_with_http_info({
        retrieve_video_request: VeniceClient::RetrieveVideoRequest.new(
          model: video_generation.model,
          queue_id: video_generation.queue_id,
          delete_media_on_completion: true
        )
      })

      content_type = headers["Content-Type"] || headers["content-type"]

      if content_type&.include?("video/mp4")
        # Video is complete - response is binary video data
        attach_video(video_generation, response)
        video_generation.update!(status: VideoGeneration::COMPLETED)
        Rails.logger.info "Video completed: #{video_generation.id}"
      else
        # Still processing - response is status object
        video_generation.update!(
          status: VideoGeneration::PROCESSING,
          average_execution_time: response.average_execution_time,
          execution_duration: response.execution_duration
        )
        Rails.logger.info "Video still processing: #{video_generation.id} - #{response.execution_duration}/#{response.average_execution_time}ms"
      end

      video_generation
    rescue VeniceClient::ApiError => e
      Rails.logger.error "Video retrieve failed: #{e.message}"
      video_generation.update!(
        status: VideoGeneration::FAILED,
        error: e.message
      )
      video_generation
    end
  end

  # Mark a video generation as complete and clean up from Venice storage
  # @param video_generation [VideoGeneration] The video generation record
  def complete(video_generation)
    return unless video_generation.queue_id.present?

    client = video_client
    return unless client

    begin
      client.complete_video({
        complete_video_request: VeniceClient::CompleteVideoRequest.new(
          model: video_generation.model,
          queue_id: video_generation.queue_id
        )
      })
      Rails.logger.info "Video cleanup completed: #{video_generation.id}"
    rescue VeniceClient::ApiError => e
      Rails.logger.warn "Video cleanup failed: #{e.message}"
    end
  end

  private

  def video_client
    api_client = @user.api_client
    return nil unless api_client

    VeniceClient::VideoApi.new(api_client)
  end

  def scene_image_data_url
    return nil unless @conversation.scene_image.attached?

    blob = @conversation.scene_image.blob
    base64_data = Base64.strict_encode64(blob.download)
    content_type = blob.content_type || "image/png"

    "data:#{content_type};base64,#{base64_data}"
  end

  def generate_action_prompt
    # Generate a short action-focused prompt based on conversation context
    # The image already captures the scene, so we focus on movement/action
    begin
      response = ChatCompletionJob.perform_now(
        @user,
        build_action_prompt_messages,
        { temperature: 0.5 }
      )

      prompt = response&.content.to_s.strip
      prompt = sanitize_prompt(prompt)

      if prompt.present? && prompt.length <= MAX_PROMPT_LENGTH
        Rails.logger.info "Generated video action prompt: #{prompt}"
        prompt
      else
        fallback_action_prompt
      end
    rescue => e
      Rails.logger.error "Failed to generate video action prompt: #{e.message}"
      fallback_action_prompt
    end
  end

  def build_action_prompt_messages
    recent_messages = @conversation.messages.order(:created_at).last(4)
    conversation_context = recent_messages.map { |m| "#{m.role}: #{m.content}" }.join("\n")

    [
      {
        role: "system",
        content: <<~SYSTEM
          You are a video prompt generator. Given a conversation context, generate a very short action prompt (under #{MAX_PROMPT_LENGTH} characters) describing subtle movement or action for a video.

          RULES:
          - Focus ONLY on movement/action, not scene description (the image handles that)
          - Keep it extremely short and direct
          - Use simple action phrases like: "gentle breathing, slight smile", "hair swaying in breeze", "turning head slowly", "blinking, subtle expression change"
          - Do not describe the character's appearance, clothing, or environment
          - Do not use camera terms or quality keywords
          - Output ONLY the action prompt, nothing else
        SYSTEM
      },
      {
        role: "user",
        content: <<~USER
          Character: #{@character.name}
          Recent conversation:
          #{conversation_context.presence || "Just started"}

          Generate a short action prompt for subtle movement in this scene:
        USER
      }
    ]
  end

  def sanitize_prompt(prompt)
    return nil if prompt.blank?

    # Remove markdown, quotes, and extra whitespace
    prompt.gsub(/```.*?```/m, "")
          .gsub(/["']/, "")
          .gsub(/\n+/, " ")
          .strip
          .first(MAX_PROMPT_LENGTH)
  end

  def fallback_action_prompt
    "subtle breathing, gentle movement, slight expression change, cinematic"
  end

  def attach_video(video_generation, video_data)
    # The response is the raw video binary data
    string_io = StringIO.new(video_data)
    string_io.set_encoding(Encoding::BINARY)

    video_generation.video.attach(
      io: string_io,
      filename: "video_#{video_generation.id}.mp4",
      content_type: "video/mp4"
    )

    Rails.logger.info "Attached video to generation #{video_generation.id}"
  end
end
