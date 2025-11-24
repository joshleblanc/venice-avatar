class StructuredTurnService
  include CharacterToolCalls

  MAX_RETRIES = 2

  def initialize(conversation)
    @conversation = conversation
    @character = conversation.character
  end

  # Generate a single natural-language reply with tool calls
  # Retries if the response is missing required content
  # Also detects and requests missing state updates
  def generate_reply(user_message_content, current_time:, opening: false)
    options = base_options
    options[:temperature] = 0.7
    options[:tools] = character_tools
    options[:tool_choice] = "required"

    retries = 0
    response = nil

    while retries <= MAX_RETRIES
      response = ChatCompletionJob.perform_now(
        @conversation.user,
        build_messages(user_message_content, current_time, opening),
        options,
        @conversation.user.text_model
      )

      # Validate response has required content
      if valid_response?(response)
        Rails.logger.info "Valid response received on attempt #{retries + 1}"
        break
      else
        retries += 1
        if retries <= MAX_RETRIES
          Rails.logger.warn "Invalid response (missing reply), retrying (#{retries}/#{MAX_RETRIES})..."
          options[:temperature] = [options[:temperature] + 0.1, 1.0].min # Slightly increase temperature
        else
          Rails.logger.error "Failed to get valid response after #{MAX_RETRIES} retries"
        end
      end
    end

    # Check for missing state updates and request them if needed
    if response && valid_response?(response)
      missing = detect_missing_state_updates(response)
      if missing.any?
        response = request_missing_state_updates(response, missing, current_time)
      end
    end

    response
  end

  # Request missing state updates from the LLM
  def request_missing_state_updates(original_response, missing, current_time)
    Rails.logger.info "Requesting missing state updates: #{missing.keys.join(', ')}"

    reply_content = extract_reply_content(original_response)

    # Build a followup request asking specifically for the missing state
    missing_tools = []
    missing_tools << "update_location" if missing[:needs_location]
    missing_tools << "update_action" if missing[:needs_action]

    followup_prompt = <<~PROMPT
      Your previous reply was: "#{reply_content}"

      This reply implies a scene change, but you didn't update the visual state.
      Please call the following tools to update the scene:
      #{missing_tools.map { |t| "- #{t}" }.join("\n")}

      Remember:
      - Each tool call should be a COMPLETE snapshot of the current state
      - Include ALL relevant details from the previous state that still apply
      - Describe the NEW location/action based on your reply
    PROMPT

    options = base_options
    options[:temperature] = 0.3  # Lower temperature for more reliable tool calls
    options[:tools] = character_tools.select { |t| missing_tools.include?(t[:function][:name]) }
    options[:tool_choice] = "required"

    begin
      followup_response = ChatCompletionJob.perform_now(
        @conversation.user,
        [
          { role: "system", content: "You are updating the visual scene state. Call the requested tools with detailed descriptions." },
          { role: "user", content: followup_prompt }
        ],
        options,
        @conversation.user.text_model
      )

      # Merge the followup tool calls into the original response
      if followup_response&.respond_to?(:tool_calls) && followup_response.tool_calls.present?
        merged_tool_calls = (original_response.tool_calls || []) + followup_response.tool_calls
        Rails.logger.info "Merged #{followup_response.tool_calls.length} additional tool calls"

        # Return a merged response object
        MergedResponse.new(
          content: original_response.content,
          tool_calls: merged_tool_calls
        )
      else
        original_response
      end
    rescue => e
      Rails.logger.error "Failed to get missing state updates: #{e.message}"
      original_response
    end
  end

  # Simple struct to hold merged response data
  class MergedResponse
    attr_reader :content, :tool_calls

    def initialize(content:, tool_calls:)
      @content = content
      @tool_calls = tool_calls
    end

    def respond_to_missing?(method, include_private = false)
      [:content, :tool_calls].include?(method) || super
    end
  end

  private

  # Check if response contains required reply content
  def valid_response?(response)
    return false if response.nil?

    # Check for reply in tool calls
    if response.respond_to?(:tool_calls) && response.tool_calls.present?
      has_reply_tool = response.tool_calls.any? do |tc|
        tc[:function][:name] == "reply" || tc.dig(:function, :name) == "reply"
      end
      return true if has_reply_tool
    end

    # Fall back to checking content
    response.respond_to?(:content) && response.content.present?
  end

  # Detect if reply implies a scene change that wasn't captured by tool calls
  # Returns hash with :needs_location, :needs_action flags
  def detect_missing_state_updates(response)
    return {} unless response.respond_to?(:tool_calls)

    reply_content = extract_reply_content(response)
    return {} if reply_content.blank?

    reply_lower = reply_content.downcase
    tool_names = (response.tool_calls || []).map { |tc| tc[:function][:name] || tc.dig(:function, :name) }

    missing = {}

    # Check for location change indicators
    location_phrases = [
      "let's go", "let's head", "follow me", "come with me",
      "we arrive", "we're at", "we're in", "here we are",
      "to the", "into the", "walk to", "head to", "go to",
      "kitchen", "bedroom", "bathroom", "living room", "outside",
      "park", "beach", "cafe", "restaurant", "office"
    ]

    has_location_indicator = location_phrases.any? { |phrase| reply_lower.include?(phrase) }
    has_location_tool = tool_names.include?("update_location")

    if has_location_indicator && !has_location_tool
      Rails.logger.warn "Reply implies location change but update_location not called: #{reply_content[0..100]}"
      missing[:needs_location] = true
    end

    # Check for action/pose change indicators
    action_phrases = [
      "sit down", "sits down", "take a seat", "stand up", "stands up",
      "lie down", "lies down", "lay down", "kneel", "crouch",
      "pick up", "put down", "grab", "hold", "reach for"
    ]

    has_action_indicator = action_phrases.any? { |phrase| reply_lower.include?(phrase) }
    has_action_tool = tool_names.include?("update_action")

    if has_action_indicator && !has_action_tool
      Rails.logger.warn "Reply implies action change but update_action not called: #{reply_content[0..100]}"
      missing[:needs_action] = true
    end

    missing
  end

  def extract_reply_content(response)
    # Try to get reply from tool call first
    if response.respond_to?(:tool_calls) && response.tool_calls.present?
      reply_call = response.tool_calls.find { |tc| tc[:function][:name] == "reply" || tc.dig(:function, :name) == "reply" }
      if reply_call
        args = reply_call[:function][:arguments]
        args = JSON.parse(args) if args.is_a?(String)
        return args["message"] if args.is_a?(Hash)
      end
    end

    # Fall back to content
    response.content if response.respond_to?(:content)
  end

  def base_options
    options = {}
    if @character.venice_created?
      options[:venice_parameters] = VeniceClient::ChatCompletionRequestVeniceParameters.new(character_slug: @character.slug)
    end
    options
  end

  def build_messages(user_message_content, current_time, opening)
    [
      {
        role: "system",
        content: system_prompt(user_message_content, current_time, opening)
      },
      {
        role: "user",
        content: user_payload(user_message_content, opening)
      }
    ]
  end

  def system_prompt(user_message_content, current_time, opening)
    <<~PROMPT
      You are #{@character.name}. Stay in character and reply naturally to the user. Be concise, present-tense, and visually grounded. Avoid describing camera work or meta-commentary.

      Current time: #{current_time}
      Character: #{@character.name}
      Description: #{@character.description}
      Scenario: #{@character.scenario_context}

      Keep continuity with prior appearance, location, and action:
      - Appearance: #{@conversation.appearance}
      - Location: #{@conversation.location}
      - Action: #{@conversation.action}

      Recent conversation (most recent last):
      #{conversation_history_snippet}

      Reply as the character only.

      #{tool_call_instructions}
    PROMPT
  end

  def user_payload(user_message_content, opening)
    prefix = opening ? "Opening context:" : "User message:"
    <<~PAYLOAD
      #{prefix} #{user_message_content}
    PAYLOAD
  end

  def conversation_history_snippet
    messages = @conversation.messages.order(:created_at).last(6)
    return "None yet." if messages.empty?

    messages.map { |m| "#{m.role}: #{m.content}" }.join("\n")
  end
end
