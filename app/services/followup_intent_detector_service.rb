class FollowupIntentDetectorService
  def initialize(conversation)
    @conversation = conversation
    @venice_client = VeniceClient::ChatApi.new
  end

  def detect_character_followup_intent(assistant_message)
    prompt = build_character_followup_detection_prompt(assistant_message)

    begin
      response = @venice_client.create_chat_completion({
        body: {
          model: "venice-uncensored",
          messages: [{ role: "user", content: prompt }],
          max_tokens: 200,
          temperature: 0.3,
        },
      })

      content = response.choices.first[:message][:content]
      Rails.logger.info "Followup intent detection response: #{content}"
      parse_followup_response(content)
    rescue => e
      Rails.logger.error "Error detecting character followup intent: #{e.message}"
      { has_intent: false, reason: nil, duration: 30 }
    end
  end

  private

  def build_character_followup_detection_prompt(assistant_message)
    recent_messages = @conversation.messages.order(:created_at).last(5)
    context = recent_messages.map { |msg| "#{msg.role}: #{msg.content}" }.join("\n")

    <<~PROMPT
      Analyze this conversation context and the AI character's latest message to determine if the character intends to step away briefly and return with a follow-up message.

      Recent conversation:
      #{context}

      Latest character message: "#{assistant_message}"

      Look for indicators that the character will step away and return, such as:
      - Saying they need to do something quickly ("let me grab something", "I'll be right back", "hold on a moment")
      - Indicating they're going to change clothes, get something, check on something
      - Mentioning they need to step away briefly but will return
      - Actions that suggest temporary departure ("*goes to get*", "*steps away to*")

      Respond with JSON only:
      {
        "has_intent": true/false,
        "reason": "brief explanation if true, null if false",
        "duration": how long they're away, in seconds
      }
    PROMPT
  end

  def parse_followup_response(content)
    # Try to extract JSON from the response
    json_match = content.match(/\{.*\}/m)
    return { has_intent: false, reason: nil, duration: 30 } unless json_match

    begin
      parsed = JSON.parse(json_match[0])
      {
        has_intent: parsed["has_intent"] || false,
        reason: parsed["reason"],
        duration: parsed["duration"] || 30,
      }
    rescue JSON::ParserError
      Rails.logger.error "Failed to parse followup intent JSON: #{content}"
      { has_intent: false, reason: nil, duration: 30 }
    end
  end
end
