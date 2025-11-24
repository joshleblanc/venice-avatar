# frozen_string_literal: true

# ConsistentPromptBuilderService
#
# Single source of truth for building image generation prompts.
# Combines locked character attributes with dynamic scene elements
# to ensure consistent character representation across all generations.
#
# This replaces the fragmented prompt generation in:
# - ScenePromptService
# - AiPromptGenerationService.generate_scene_from_character_description
#
class ConsistentPromptBuilderService
  QUALITY_TAGS = "masterpiece, best quality, ultra-detailed, HDR, sharp focus, depth of field".freeze

  NEGATIVE_PROMPT = [
    "worst quality", "low quality", "blurry", "out of focus",
    "deformed", "disfigured", "bad anatomy", "bad proportions",
    "extra limbs", "mutated hands", "fused fingers",
    "duplicate", "clone", "multiple people",
    "child", "minor", "young", "teen", "teenager",
    "inconsistent features", "morphing"
  ].join(", ").freeze

  def initialize(conversation)
    @conversation = conversation
    @character = conversation.character
    @consistency_service = CharacterConsistencyService.new(conversation)
  end

  # Build a complete, consistent prompt for image generation
  # @param trigger [String] What triggered this generation (for logging)
  # @return [Hash] Contains :prompt, :negative_prompt, and :seed
  def build(trigger: "unknown")
    Rails.logger.info "Building consistent prompt for conversation #{@conversation.id} (trigger: #{trigger})"

    prompt_parts = [
      quality_prefix,
      locked_appearance_section,
      clothing_section,
      action_section,
      location_section
    ].compact.reject(&:blank?)

    full_prompt = prompt_parts.join(", ")

    # Validate and filter content
    validated_prompt = validate_content(full_prompt)

    {
      prompt: validated_prompt,
      negative_prompt: build_negative_prompt,
      seed: @conversation.seed || generate_and_store_seed
    }
  end

  # Build prompt specifically for a scene update (after tool calls)
  def build_for_scene_update
    build(trigger: "scene_update")
  end

  # Build prompt for initial scene generation
  def build_for_initial_scene
    # For initial scenes, we may need to extract appearance first
    ensure_locked_appearance!
    build(trigger: "initial")
  end

  # Build prompt from explicit appearance/location/action (for tool call updates)
  def build_from_state(appearance:, location:, action:)
    Rails.logger.info "Building prompt from explicit state"

    prompt_parts = [
      quality_prefix,
      extract_permanent_features(appearance),
      extract_clothing(appearance),
      action.presence,
      build_location_tags(location)
    ].compact.reject(&:blank?)

    full_prompt = prompt_parts.join(", ")
    validate_content(full_prompt)
  end

  private

  def quality_prefix
    QUALITY_TAGS
  end

  def locked_appearance_section
    locked = @consistency_service.locked_appearance_tags
    return nil if locked.blank?

    # Wrap in parentheses with weight boost for emphasis
    "(#{locked}:1.2)"
  end

  def clothing_section
    appearance = @conversation.appearance
    return nil if appearance.blank?

    clothing = extract_clothing(appearance)
    return nil if clothing.blank?

    clothing
  end

  def action_section
    action = @conversation.action
    return nil if action.blank?

    # Clean up action text for image prompts
    clean_action(action)
  end

  def location_section
    location = @conversation.location
    return nil if location.blank?

    build_location_tags(location)
  end

  def extract_clothing(appearance_text)
    return nil if appearance_text.blank?

    # Clothing-related keywords
    clothing_indicators = %w[
      wearing wears dressed shirt blouse top dress skirt pants jeans shorts
      jacket coat sweater hoodie uniform clothes outfit
      shoes boots heels sneakers sandals barefoot
      hat cap scarf gloves jewelry necklace bracelet earrings ring
      bra panties underwear lingerie swimsuit bikini
      socks stockings tights
    ]

    # Split into sentences and filter for clothing mentions
    sentences = appearance_text.split(/[.!?]+/)
    clothing_sentences = sentences.select do |sentence|
      clothing_indicators.any? { |indicator| sentence.downcase.include?(indicator) }
    end

    return nil if clothing_sentences.empty?

    # Clean and join
    clothing_sentences.map(&:strip).join(", ").gsub(/\s+/, " ").strip
  end

  def extract_permanent_features(appearance_text)
    return nil if appearance_text.blank?

    # Non-clothing physical features
    feature_indicators = %w[
      hair eyes skin face body tall short petite slim slender
      athletic curvy muscular build height complexion
      cheekbones lips nose forehead chin jawline
      bust chest waist hips thighs legs arms
    ]

    sentences = appearance_text.split(/[.!?]+/)
    feature_sentences = sentences.select do |sentence|
      sentence_lower = sentence.downcase
      # Include if it mentions features but isn't primarily about clothing
      feature_indicators.any? { |f| sentence_lower.include?(f) } &&
        !sentence_lower.include?("wearing") &&
        !sentence_lower.include?("dressed")
    end

    return nil if feature_sentences.empty?

    feature_sentences.map(&:strip).join(", ").gsub(/\s+/, " ").strip
  end

  def clean_action(action_text)
    # Remove instructional language and focus on visual description
    cleaned = action_text.dup

    # Remove negative instructions (keep for negative prompt instead)
    cleaned.gsub!(/NOT\s+\w+,?\s*/i, "")
    cleaned.gsub!(/NEVER\s+\w+,?\s*/i, "")

    # Remove redundant phrases
    cleaned.gsub!(/\b(currently|presently|right now)\b/i, "")
    cleaned.gsub!(/\s+/, " ")

    cleaned.strip
  end

  def build_location_tags(location_text)
    return nil if location_text.blank?

    # Extract key location elements and format as tags
    location_text
      .gsub(/\b(The|A|An)\b/i, "")
      .gsub(/\s+/, " ")
      .strip
  end

  def build_negative_prompt
    base = NEGATIVE_PROMPT

    # Add character-specific negatives
    locked = @consistency_service.locked_appearance_tags
    if locked.present?
      character_negatives = @consistency_service.send(:generate_attribute_negatives, locked)
      base = [base, character_negatives.join(", ")].reject(&:blank?).join(", ")
    end

    base
  end

  def validate_content(prompt)
    return prompt if prompt.blank?

    # Child-related terms to filter
    child_terms = %w[
      child children kid kids baby babies toddler infant minor minors
      boy boys girl girls son daughter nephew niece student students
      youngster youth juvenile adolescent teen teens teenager preteen tween
    ]

    filtered = prompt.dup

    # Remove sentences containing child terms
    sentences = filtered.split(/[.!?]+/)
    safe_sentences = sentences.reject do |sentence|
      child_terms.any? { |term| sentence.downcase.include?(term.downcase) }
    end

    if safe_sentences.empty?
      return "adult character in a comfortable setting, detailed, high quality"
    end

    result = safe_sentences.join(". ").strip
    result += "." unless result.end_with?(".")

    # Ensure "adult" is present
    unless result.downcase.include?("adult")
      result = "adult #{result}"
    end

    result
  end

  def ensure_locked_appearance!
    return if @consistency_service.locked_appearance_tags.present?

    # Try to extract from available sources
    source = @character.appearance || @conversation.appearance || @character.description
    if source.present?
      @consistency_service.extract_locked_attributes(source)
    end
  end

  def generate_and_store_seed
    new_seed = rand(1..999_999_999)
    @conversation.update!(seed: new_seed)
    new_seed
  end
end
