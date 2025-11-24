# frozen_string_literal: true

# CharacterConsistencyService
#
# Manages consistent character representation across image generations.
# Extracts and locks core visual attributes that should remain constant,
# while allowing dynamic elements (action, expression, location) to change.
#
# Usage:
#   service = CharacterConsistencyService.new(conversation)
#   locked_appearance = service.locked_appearance_tags
#   full_prompt = service.build_consistent_prompt(dynamic_elements)
#
class CharacterConsistencyService
  # Core attributes that should NEVER change across generations
  LOCKED_CATEGORIES = %i[
    body_type
    height
    skin_tone
    hair_color
    hair_length
    hair_style
    eye_color
    face_shape
    distinguishing_features
  ].freeze

  # Attributes that can change with conversation context
  DYNAMIC_CATEGORIES = %i[
    clothing
    accessories
    expression
    pose
    action
  ].freeze

  def initialize(conversation)
    @conversation = conversation
    @character = conversation.character
  end

  # Extract and return locked appearance attributes as a consistent string
  # These are stored on first generation and reused for all subsequent images
  def locked_appearance_tags
    cached = @conversation.metadata&.dig("locked_appearance")
    return cached if cached.present?

    # Extract from character appearance or generate from description
    source = @character.appearance || @conversation.appearance || @character.description
    return nil if source.blank?

    extracted = extract_locked_attributes(source)
    store_locked_appearance(extracted)
    extracted
  end

  # Build a complete prompt with locked attributes prepended
  # This ensures core features are always present and prioritized
  def build_consistent_prompt(dynamic_prompt)
    locked = locked_appearance_tags
    return dynamic_prompt if locked.blank?

    # Structure: locked features first (highest weight), then dynamic elements
    [
      quality_prefix,
      "(#{locked}:1.3)",  # Boost locked features with weight
      dynamic_prompt,
      negative_prompt_suffix
    ].compact.join(", ")
  end

  # Generate a canonical prompt combining locked and dynamic elements
  def canonical_scene_prompt
    locked = locked_appearance_tags
    dynamic = build_dynamic_elements

    return fallback_prompt if locked.blank? && dynamic.blank?

    components = [
      quality_prefix,
      locked.present? ? "(#{locked}:1.3)" : nil,
      dynamic,
      scene_atmosphere
    ].compact

    components.join(", ").strip
  end

  # Extract core visual attributes from a description
  def extract_locked_attributes(source_description)
    return nil if source_description.blank?

    prompt = build_extraction_prompt(source_description)

    begin
      response = ChatCompletionJob.perform_now(@conversation.user, [
        { role: "user", content: prompt }
      ], { temperature: 0.1 }) # Very low temperature for consistency

      extracted = response.content.strip
      Rails.logger.info "Extracted locked attributes: #{extracted[0..200]}..."
      extracted
    rescue => e
      Rails.logger.error "Failed to extract locked attributes: #{e.message}"
      extract_attributes_via_regex(source_description)
    end
  end

  # Force refresh of locked attributes (use sparingly)
  def refresh_locked_appearance!
    source = @character.appearance || @conversation.appearance || @character.description
    return nil if source.blank?

    extracted = extract_locked_attributes(source)
    store_locked_appearance(extracted)
    extracted
  end

  # Get the negative prompt to prevent drift
  def negative_prompt
    base_negatives = [
      "inconsistent features",
      "changing appearance",
      "morphing",
      "multiple people",
      "duplicate",
      "clone",
      "child",
      "minor",
      "young"
    ]

    # Add character-specific negatives based on locked attributes
    locked = locked_appearance_tags
    if locked.present?
      # If character has brown hair, add "blonde hair, red hair" etc to negatives
      base_negatives += generate_attribute_negatives(locked)
    end

    base_negatives.uniq.join(", ")
  end

  private

  def build_extraction_prompt(source_description)
    <<~PROMPT
      Extract ONLY the permanent physical attributes from this character description.
      Return a comma-separated list of visual tags suitable for image generation.

      EXTRACT ONLY:
      - Body type (height, build, proportions)
      - Skin tone (specific color)
      - Hair (color, length, style - e.g., "long black straight hair")
      - Eye color (e.g., "blue eyes")
      - Face shape and features (e.g., "heart-shaped face, full lips")
      - Distinguishing marks (scars, moles, tattoos)
      - Species/race if non-human

      DO NOT EXTRACT:
      - Clothing (changes)
      - Accessories (can change)
      - Expression (changes)
      - Pose (changes)
      - Location (changes)
      - Actions (changes)

      FORMAT: Return ONLY comma-separated tags, no explanation.
      Example: "adult woman, tall, slender build, fair skin, long wavy auburn hair, green eyes, oval face, high cheekbones, small mole on left cheek"

      SOURCE DESCRIPTION:
      #{source_description}

      EXTRACTED PERMANENT ATTRIBUTES:
    PROMPT
  end

  def extract_attributes_via_regex(source)
    # Fallback regex extraction for common attributes
    attributes = []

    # Hair patterns
    if source =~ /((?:long|short|medium|shoulder-length)\s+(?:\w+\s+)?(?:hair|locks))/i
      attributes << $1.downcase
    end
    if source =~ /((?:blonde|brown|black|red|auburn|silver|white|pink|blue|purple|green)\s+hair)/i
      attributes << $1.downcase
    end

    # Eye patterns
    if source =~ /((?:blue|brown|green|hazel|amber|grey|gray|violet|red|golden)\s+eyes?)/i
      attributes << $1.downcase
    end

    # Skin patterns
    if source =~ /((?:fair|pale|light|tan|olive|dark|brown|black|ebony)\s+skin)/i
      attributes << $1.downcase
    end

    # Build patterns
    if source =~ /((?:tall|short|petite|average|slim|slender|athletic|curvy|muscular)\s+(?:build|frame|figure)?)/i
      attributes << $1.downcase.strip
    end

    # Always add adult
    attributes.unshift("adult")

    attributes.uniq.join(", ")
  end

  def store_locked_appearance(appearance_string)
    metadata = @conversation.metadata || {}
    metadata["locked_appearance"] = appearance_string
    metadata["locked_appearance_at"] = Time.current.iso8601
    @conversation.update!(metadata: metadata)

    Rails.logger.info "Stored locked appearance for conversation #{@conversation.id}"
  end

  def build_dynamic_elements
    elements = []

    # Current clothing from conversation state
    if @conversation.appearance.present?
      clothing = extract_clothing_only(@conversation.appearance)
      elements << clothing if clothing.present?
    end

    # Current action/pose
    if @conversation.action.present?
      elements << @conversation.action
    end

    # Current expression (extract from action or appearance)
    expression = extract_expression(@conversation.action || @conversation.appearance)
    elements << expression if expression.present?

    elements.join(", ")
  end

  def extract_clothing_only(appearance)
    # Extract clothing-related terms from appearance
    clothing_keywords = %w[
      wearing shirt blouse top dress skirt pants jeans shorts
      jacket coat sweater hoodie uniform outfit clothes
      shoes boots heels sneakers sandals barefoot
      hat cap scarf gloves jewelry necklace bracelet earrings
      bra underwear lingerie swimsuit bikini
    ]

    words = appearance.downcase.split(/[\s,]+/)
    sentences = appearance.split(/[.!?]+/)

    clothing_sentences = sentences.select do |sentence|
      clothing_keywords.any? { |kw| sentence.downcase.include?(kw) }
    end

    clothing_sentences.join(". ").strip
  end

  def extract_expression(text)
    return nil if text.blank?

    expression_patterns = [
      /(\w+\s+expression)/i,
      /(\w+\s+smile)/i,
      /(\w+\s+gaze)/i,
      /(smiling|frowning|serious|happy|sad|neutral|confident|shy)/i
    ]

    expression_patterns.each do |pattern|
      if text =~ pattern
        return $1.downcase
      end
    end

    nil
  end

  def generate_attribute_negatives(locked_attributes)
    negatives = []

    # Hair color negatives
    hair_colors = %w[blonde brunette black brown red auburn silver white pink blue purple green]
    current_hair = hair_colors.find { |c| locked_attributes.downcase.include?(c) }
    if current_hair
      negatives += (hair_colors - [current_hair]).map { |c| "#{c} hair" }
    end

    # Eye color negatives
    eye_colors = %w[blue brown green hazel amber grey violet red golden]
    current_eyes = eye_colors.find { |c| locked_attributes.downcase.include?(c) }
    if current_eyes
      negatives += (eye_colors - [current_eyes]).map { |c| "#{c} eyes" }
    end

    negatives
  end

  def quality_prefix
    "masterpiece, best quality, ultra-detailed, sharp focus, adult character"
  end

  def scene_atmosphere
    location = @conversation.location
    return nil if location.blank?

    # Extract lighting and atmosphere from location
    if location =~ /((?:warm|cold|soft|harsh|dim|bright|natural|artificial)\s+lighting)/i
      return $1.downcase
    end

    nil
  end

  def negative_prompt_suffix
    nil # Negative prompts handled separately
  end

  def fallback_prompt
    "adult character, detailed, high quality, masterpiece"
  end
end
