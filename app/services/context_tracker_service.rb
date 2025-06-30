class ContextTrackerService
  def initialize(conversation)
    @conversation = conversation
    @character = conversation.character
  end

  def analyze_message_context(message_content, role)
    context_changes = {
      location_change: detect_location_change(message_content),
      appearance_change: detect_appearance_change(message_content),
      expression_change: detect_expression_change(message_content),
      clothing_change: detect_clothing_change(message_content),
      injury_change: detect_injury_change(message_content),
    }

    create_character_state_if_needed(context_changes, message_content, role)
  end

  private

  def detect_location_change(content)
    location_keywords = [
      /(?:go|went|move|travel|walk|run|enter|exit|arrive|leave)\s+(?:to|into|from|at)\s+([^.!?]+)/i,
      /(?:in|at|inside|outside|near)\s+(?:the|a|an)?\s*([^.!?]+)/i,
      /location[:\s]+([^.!?]+)/i,
    ]

    location_keywords.each do |pattern|
      match = content.match(pattern)
      return match[1].strip if match
    end

    nil
  end

  def detect_appearance_change(content)
    appearance_keywords = [
      /(?:look|appear|seem|become)\s+([^.!?]+)/i,
      /(?:hair|eyes|skin|face)\s+(?:is|are|look|appear)\s+([^.!?]+)/i,
      /appearance[:\s]+([^.!?]+)/i,
    ]

    appearance_keywords.each do |pattern|
      match = content.match(pattern)
      return match[1].strip if match
    end

    nil
  end

  def detect_expression_change(content)
    expression_keywords = [
      /(?:smile|frown|laugh|cry|angry|sad|happy|excited|worried|confused|surprised|shocked)/i,
      /(?:expression|face)\s+(?:is|shows|displays)\s+([^.!?]+)/i,
      /(?:feel|feeling)\s+([^.!?]+)/i,
    ]

    expression_keywords.each do |pattern|
      match = content.match(pattern)
      return match.to_s.strip if match
    end

    nil
  end

  def detect_clothing_change(content)
    clothing_keywords = [
      /(?:wear|wearing|put on|take off|change into|dressed in)\s+([^.!?]+)/i,
      /(?:clothes|clothing|outfit|dress|shirt|pants|shoes)\s+([^.!?]+)/i,
    ]

    clothing_keywords.each do |pattern|
      match = content.match(pattern)
      return match[1].strip if match
    end

    nil
  end

  def detect_injury_change(content)
    injury_keywords = [
      /(?:hurt|injured|wounded|bleeding|bruised|cut|scratched|damaged)/i,
      /(?:pain|ache|sore)\s+(?:in|on)\s+([^.!?]+)/i,
      /(?:bandage|heal|recover|medicine)/i,
    ]

    injury_keywords.each do |pattern|
      match = content.match(pattern)
      return match.to_s.strip if match
    end

    nil
  end

  def create_character_state_if_needed(context_changes, message_content, role)
    # Only create new state if there are significant changes
    significant_changes = context_changes.select { |key, value|
      value.present? && is_significant_change?(key, value, message_content)
    }

    return @conversation.current_character_state unless significant_changes.any?

    previous_state = @conversation.current_character_state

    new_state = @conversation.character_states.build(
      location: context_changes[:location_change] || previous_state&.location,
      appearance_description: build_appearance_description(context_changes, previous_state),
      expression: context_changes[:expression_change] || previous_state&.expression,
      clothing_details: build_clothing_details(context_changes, previous_state),
      injury_details: build_injury_details(context_changes, previous_state),
      background_prompt: build_background_prompt(context_changes, previous_state),
      message_context: message_content,
      triggered_by_role: role,
    )

    # Initialize detailed character description for consistent image generation
    new_state.initialize_base_character_description(@conversation.character)

    # Only save if there are actual visual changes needed
    if new_state.needs_background_update?(previous_state) ||
       new_state.needs_character_update?(previous_state)
      new_state.save!
      # Copy images from previous state if no visual change is needed
      copy_images_if_unchanged(new_state, previous_state)
    else
      # Return previous state if no changes needed
      return previous_state
    end

    new_state
  end

  def is_significant_change?(change_type, value, message_content)
    case change_type
    when :location_change
      # Only consider explicit location changes significant
      message_content.match?(/(?:go|went|move|travel|walk|run|enter|exit|arrive|leave)\s+(?:to|into|from)/i)
    when :appearance_change
      # Only consider explicit appearance descriptions significant
      message_content.match?(/(?:appearance|look like|transform|change)/i)
    when :clothing_change
      # Only consider explicit clothing changes significant
      message_content.match?(/(?:wear|put on|take off|dress|outfit|clothes)/i)
    when :injury_change
      # Only consider explicit injury mentions significant
      message_content.match?(/(?:hurt|injured|wound|pain|damage|heal)/i)
    when :expression_change
      # Be more selective about expressions - only strong emotional words
      message_content.match?(/(?:smile|frown|laugh|cry|angry|furious|terrified|overjoyed)/i)
    else
      false
    end
  end

  def copy_images_if_unchanged(new_state, previous_state)
    return unless previous_state

    # Copy character image if appearance hasn't changed
    if previous_state.character_image.attached? && !new_state.appearance_changed?(previous_state)
      new_state.character_image.attach(previous_state.character_image.blob)
    end

    # Copy background image if location hasn't changed
    if previous_state.background_image.attached? && !new_state.location_changed?(previous_state)
      new_state.background_image.attach(previous_state.background_image.blob)
    end
  end

  def build_appearance_description(context_changes, previous_state)
    base_description = previous_state&.appearance_description || @character.description || "A character"

    if context_changes[:appearance_change]
      "#{base_description}. #{context_changes[:appearance_change]}"
    else
      base_description
    end
  end

  def build_clothing_details(context_changes, previous_state)
    details = previous_state&.clothing_details || {}

    if context_changes[:clothing_change]
      details.merge(latest_change: context_changes[:clothing_change], updated_at: Time.current)
    else
      details
    end
  end

  def build_injury_details(context_changes, previous_state)
    details = previous_state&.injury_details || {}

    if context_changes[:injury_change]
      details.merge(latest_injury: context_changes[:injury_change], updated_at: Time.current)
    else
      details
    end
  end

  def build_background_prompt(context_changes, previous_state)
    if context_changes[:location_change]
      "Visual novel style background of #{context_changes[:location_change]}, static and detailed"
    else
      previous_state&.background_prompt || "A cozy indoor setting with warm lighting"
    end
  end
end
