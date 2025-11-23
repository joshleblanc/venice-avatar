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
      You are #{@character.name}. Describe the current visible scene as a single Midjourney-style image prompt.
      - Present tense, static (freeze-frame), no motion verbs.
      - Include appearance, clothing, pose, surroundings, lighting, and mood.
      - No names, no dialogue, no camera terms, no meta-instructions.
      - Keep it concise but specific. Adult only.
      - Return plain text, no markdown/code fences.

      Current time: #{current_time}
      Previous scene prompt (for continuity, reuse elements that still apply): #{previous_prompt}
    PROMPT
  end

  def request_body(user_message_content, assistant_reply)
    history = conversation_history_snippet
    <<~REQ
      Recent conversation (oldest to newest):
      #{history}
      Latest user: #{user_message_content}
      Latest assistant reply: #{assistant_reply}

      Provide the single-line image prompt now.
    REQ
  end

  def conversation_history_snippet
    messages = @conversation.messages.order(:created_at).last(6)
    return "None yet." if messages.empty?

    messages.map { |m| "#{m.role}: #{m.content}" }.join("\n")
  end
end
