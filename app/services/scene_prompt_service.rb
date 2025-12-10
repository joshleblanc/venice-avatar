class ScenePromptService
  def initialize(conversation)
    @conversation = conversation
    @character = conversation.character
  end

  def generate_prompt(user_message_content, assistant_reply, current_time:, previous_prompt: nil)
    options = base_options
    options[:temperature] = 0.25

    response = ChatCompletionJob.perform_now(
      @conversation.user,
      build_messages(user_message_content, assistant_reply, current_time, previous_prompt),
      options,
      @conversation.user.text_model
    )

    prompt = response&.content.to_s.strip
    return nil if prompt.blank?

    # Ensure no markdown fences
    prompt.gsub!(/```.*?```/m, "")
    prompt.strip!
    prompt
  rescue => e
    Rails.logger.error "Failed to generate scene prompt: #{e.message}"
    nil
  end

  private

  def base_options
    opts = {}
    if @character.venice_created?
      opts[:venice_parameters] = VeniceClient::ChatCompletionRequestVeniceParameters.new(character_slug: @character.slug)
    end
    opts
  end

  def build_messages(user_message_content, assistant_reply, current_time, previous_prompt)
    [
      {
        role: "system",
        content: system_prompt(current_time, previous_prompt)
      },
      {
        role: "user",
        content: request_body(user_message_content, assistant_reply)
      }
    ]
  end

  def system_prompt(current_time, previous_prompt)
    <<~PROMPT
      You are #{@character.name}. Write a detailed, vivid description of the current scene as if painting a picture with words.

      DESCRIPTION STYLE:
      - Write in flowing, descriptive prose—not keywords or comma-separated tags.
      - Use complete sentences that describe what the viewer sees.
      - Be specific and concrete: describe exact colors, textures, materials, and positions.
      - Present tense, static moment frozen in time.

      INCLUDE:
      - The character's physical appearance: face, body, skin, hair (color, length, style).
      - Current clothing: specific garments, colors, fabrics, how they fit and drape.
      - Expression and pose: what emotion shows on the face, body position, hand placement.
      - The environment: where are they, what objects surround them, the space and its details.
      - Lighting: source, quality, color temperature, how it falls on the character and scene.
      - Atmosphere: the mood, ambient details, depth and texture of the space.

      DO NOT INCLUDE:
      - Names or dialogue.
      - Camera/photography terms (no "shot of", "framing", "lens").
      - Quality keywords like "masterpiece", "4k", "HDR", etc.
      - Motion or action verbs—describe the frozen moment, not movement.

      CONTINUITY:
      If there is a previous scene description, keep all physical traits (face, body, hair) exactly the same.
      Only change what the conversation indicates has changed (clothing, pose, location, expression).

      Current time: #{current_time}
      Previous scene description (maintain character consistency): #{previous_prompt.presence || "None yet"}
    PROMPT
  end

  def request_body(user_message_content, assistant_reply)
    history = conversation_history_snippet
    <<~REQ
      Recent conversation (oldest to newest):
      #{history}
      Latest user: #{user_message_content}
      Latest assistant reply: #{assistant_reply}

      Write the scene description now. Be detailed and specific.
    REQ
  end

  def conversation_history_snippet
    messages = @conversation.messages.order(:created_at).last(6)
    return "None yet." if messages.empty?

    messages.map { |m| "#{m.role}: #{m.content}" }.join("\n")
  end
end
