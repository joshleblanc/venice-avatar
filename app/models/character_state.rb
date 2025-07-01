class CharacterState < ApplicationRecord
  belongs_to :conversation, touch: true

  # Active Storage attachments for generated images
  has_one_attached :character_image
  has_one_attached :background_image
  has_one_attached :scene_image  # Unified character + background image

  validates :conversation_id, presence: true

  # Character appearance tracking
  # JSON columns handle serialization automatically

  # Image URLs for generated content
  validates :background_image_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true }
  validates :character_image_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true }

  scope :recent, -> { order(created_at: :desc) }

  # Initialize detailed character attributes with defaults
  after_initialize :set_default_attributes, if: :new_record?

  # Background description fields for consistency
  # These will be stored in existing text fields or JSON columns

  # Detailed character description methods
  def initialize_base_character_description(character)
    Rails.logger.info "Initializing base character description for character: #{character&.name}"
    return if base_character_prompt.present?

    begin
      # Build comprehensive base description from character data
      self.base_character_prompt = build_comprehensive_character_description(character)
      self.physical_features = extract_physical_features(character)
      self.hair_details = extract_hair_details(character)
      self.eye_details = extract_eye_details(character)
      self.body_type = extract_body_type(character)
      self.skin_tone = extract_skin_tone(character)
      self.distinctive_features = extract_distinctive_features(character)
      self.default_outfit = extract_default_outfit(character)
      self.pose_style = "standing pose, full body portrait"
      self.art_style_notes = "visual novel character art, anime art style, high quality, detailed"

      Rails.logger.info "Successfully initialized detailed character attributes"
    rescue => e
      Rails.logger.error "Failed to initialize base character description: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      raise e
    end
  end

  def build_detailed_character_prompt
    prompt_parts = []

    # Start with base character description
    prompt_parts << base_character_prompt if base_character_prompt.present?

    # Add physical features
    if physical_features.present?
      prompt_parts << format_physical_features
    end

    # Add hair details
    if hair_details.present?
      prompt_parts << format_hair_details
    end

    # Add eye details
    if eye_details.present?
      prompt_parts << format_eye_details
    end

    # Add body type and skin tone
    prompt_parts << body_type if body_type.present?
    prompt_parts << "#{skin_tone} skin" if skin_tone.present?

    # Add distinctive features
    if distinctive_features.present?
      prompt_parts << format_distinctive_features
    end

    # Add current expression (this is what changes)
    prompt_parts << "with #{expression} expression" if expression.present?

    # Add current clothing (this can change)
    if clothing_details.present? && clothing_details["latest_change"]
      prompt_parts << "wearing #{clothing_details["latest_change"]}"
    elsif default_outfit.present?
      prompt_parts << format_default_outfit
    end

    # Add injury details if present
    if injury_details.present? && injury_details["latest_injury"]
      prompt_parts << "showing #{injury_details["latest_injury"]}"
    end

    # Add pose and art style
    prompt_parts << pose_style if pose_style.present?
    prompt_parts << art_style_notes if art_style_notes.present?

    prompt_parts.compact.join(", ")
  end

  def appearance_changed?(previous_state)
    return true if previous_state.nil?

    appearance_description != previous_state.appearance_description ||
      expression != previous_state.expression ||
      clothing_details != previous_state.clothing_details ||
      injury_details != previous_state.injury_details
  end

  def location_changed?(previous_state)
    return true if previous_state.nil?

    location != previous_state.location ||
      background_prompt != previous_state.background_prompt
  end

  def needs_background_update?(previous_state)
    location_changed?(previous_state) || background_image_url.blank?
  end

  def needs_character_update?(previous_state)
    appearance_changed?(previous_state) || character_image_url.blank?
  end

  def set_default_attributes
    self.pose_style ||= "standing pose, full body portrait"
    self.art_style_notes ||= "visual novel character art, anime art style, high quality, detailed"
  end

  def build_comprehensive_character_description(character)
    # Extract detailed description from character's description or tags
    base_desc = character.description.to_s

    # If description is too brief, enhance it with character name and basic info
    if base_desc.length < 50
      "#{character.name}, #{base_desc}"
    else
      base_desc
    end
  end

  def extract_physical_features(character)
    # Parse character description for physical features
    features = {}
    desc = character.description.to_s.downcase

    # Extract age-related terms
    if desc.match?(/(young|teen|adult|mature|elderly)/)
      features["age_appearance"] = desc.match(/(young|teen|adult|mature|elderly)/)[1]
    end

    # Extract height references
    if desc.match?(/(tall|short|average height|petite)/)
      features["height"] = desc.match(/(tall|short|average height|petite)/)[1]
    end

    features
  end

  def extract_hair_details(character)
    desc = character.description.to_s.downcase
    hair = {}

    # Hair color
    colors = %w[black brown blonde red silver white pink blue green purple orange]
    colors.each do |color|
      if desc.include?("#{color} hair")
        hair["color"] = color
        break
      end
    end

    # Hair length
    lengths = ["long hair", "short hair", "medium hair", "shoulder-length"]
    lengths.each do |length|
      if desc.include?(length)
        hair["length"] = length
        break
      end
    end

    # Hair style
    styles = %w[straight curly wavy braided ponytail twintails]
    styles.each do |style|
      if desc.include?(style)
        hair["style"] = style
        break
      end
    end

    hair
  end

  def extract_eye_details(character)
    desc = character.description.to_s.downcase
    eyes = {}

    # Eye color
    colors = %w[blue green brown hazel gray amber violet red golden]
    colors.each do |color|
      if desc.include?("#{color} eyes")
        eyes["color"] = color
        break
      end
    end

    eyes
  end

  def extract_body_type(character)
    desc = character.description.to_s.downcase

    body_types = ["slender", "athletic", "curvy", "petite", "average build"]
    body_types.each do |type|
      return type if desc.include?(type)
    end

    "average build" # default
  end

  def extract_skin_tone(character)
    desc = character.description.to_s.downcase

    tones = ["pale", "fair", "light", "medium", "tan", "dark", "olive"]
    tones.each do |tone|
      return tone if desc.include?("#{tone} skin")
    end

    "fair" # default
  end

  def extract_distinctive_features(character)
    features = []
    desc = character.description.to_s.downcase

    # Look for distinctive features
    distinctive_terms = ["scar", "tattoo", "piercing", "glasses", "freckles", "dimples"]
    distinctive_terms.each do |term|
      if desc.include?(term)
        features << term
      end
    end

    { "features" => features }
  end

  def extract_default_outfit(character)
    desc = character.description.to_s.downcase
    outfit = {}

    # Look for clothing mentions
    clothing_terms = ["dress", "shirt", "blouse", "skirt", "pants", "jeans", "uniform", "kimono"]
    clothing_terms.each do |term|
      if desc.include?(term)
        outfit["type"] = term
        break
      end
    end

    outfit
  end

  def format_physical_features
    return "" unless physical_features.present?

    parts = []
    parts << physical_features["age_appearance"] if physical_features["age_appearance"]
    parts << physical_features["height"] if physical_features["height"]

    parts.join(", ")
  end

  def format_hair_details
    return "" unless hair_details.present?

    parts = []
    parts << hair_details["length"] if hair_details["length"]
    parts << hair_details["color"] if hair_details["color"]
    parts << hair_details["style"] if hair_details["style"]

    parts.any? ? parts.join(" ") + " hair" : ""
  end

  def format_eye_details
    return "" unless eye_details.present?

    eye_details["color"] ? "#{eye_details["color"]} eyes" : ""
  end

  def format_distinctive_features
    return "" unless distinctive_features.present? && distinctive_features["features"]

    features = distinctive_features["features"]
    features.any? ? "with #{features.join(", ")}" : ""
  end

  def format_default_outfit
    return "" unless default_outfit.present?

    default_outfit["type"] ? "wearing #{default_outfit["type"]}" : ""
  end

  # Detailed background description methods for unified scene generation
  def initialize_detailed_background_description
    Rails.logger.info "Initializing detailed background description"
    return if detailed_background_info.present?

    begin
      # Build comprehensive background description from current background_prompt
      base_location = background_prompt || "A cozy indoor setting with warm lighting"

      # Create detailed background information for consistency
      self.detailed_background_info = {
        "base_environment" => extract_base_environment(base_location),
        "lighting_conditions" => extract_lighting_conditions(base_location),
        "architectural_details" => extract_architectural_details(base_location),
        "atmospheric_elements" => extract_atmospheric_elements(base_location),
        "color_palette" => extract_color_palette(base_location),
        "furniture_objects" => extract_furniture_objects(base_location),
        "time_of_day" => extract_time_of_day(base_location),
        "weather_conditions" => extract_weather_conditions(base_location),
      }

      Rails.logger.info "Successfully initialized detailed background information"
    rescue => e
      Rails.logger.error "Failed to initialize detailed background description: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      # Set minimal fallback
      self.detailed_background_info = {
        "base_environment" => "indoor room",
        "lighting_conditions" => "warm lighting",
        "atmospheric_elements" => "cozy atmosphere",
      }
    end
  end

  def build_detailed_background_prompt
    return "a cozy indoor setting" unless detailed_background_info.present?

    prompt_parts = []

    # Base environment
    if detailed_background_info["base_environment"]
      prompt_parts << detailed_background_info["base_environment"]
    end

    # Architectural details
    if detailed_background_info["architectural_details"]
      prompt_parts << "with #{detailed_background_info["architectural_details"]}"
    end

    # Furniture and objects
    if detailed_background_info["furniture_objects"]
      prompt_parts << "featuring #{detailed_background_info["furniture_objects"]}"
    end

    # Lighting conditions
    if detailed_background_info["lighting_conditions"]
      prompt_parts << "#{detailed_background_info["lighting_conditions"]}"
    end

    # Atmospheric elements
    if detailed_background_info["atmospheric_elements"]
      prompt_parts << "#{detailed_background_info["atmospheric_elements"]}"
    end

    # Time and weather context
    time_weather = []
    time_weather << detailed_background_info["time_of_day"] if detailed_background_info["time_of_day"]
    time_weather << detailed_background_info["weather_conditions"] if detailed_background_info["weather_conditions"]

    if time_weather.any?
      prompt_parts << "during #{time_weather.join(", ")}"
    end

    # Color palette
    if detailed_background_info["color_palette"]
      prompt_parts << "with #{detailed_background_info["color_palette"]} color scheme"
    end

    prompt_parts.compact.join(", ")
  end

  def background_needs_update?(previous_state)
    return true if previous_state.nil?
    return true if location != previous_state.location
    return true if background_prompt != previous_state.background_prompt

    # Check if detailed background info has changed significantly
    if detailed_background_info.present? && previous_state.detailed_background_info.present?
      key_elements = ["base_environment", "lighting_conditions", "time_of_day", "weather_conditions"]
      key_elements.any? do |key|
        detailed_background_info[key] != previous_state.detailed_background_info[key]
      end
    else
      detailed_background_info != previous_state.detailed_background_info
    end
  end

  # Background extraction helper methods
  def extract_base_environment(location_text)
    text = location_text.to_s.downcase

    # Indoor environments
    return "cozy living room" if text.include?("living room") || text.include?("cozy")
    return "modern bedroom" if text.include?("bedroom")
    return "spacious kitchen" if text.include?("kitchen")
    return "elegant dining room" if text.include?("dining")
    return "home office study" if text.include?("office") || text.include?("study")
    return "comfortable library" if text.include?("library")

    # Outdoor environments
    return "peaceful garden" if text.include?("garden") || text.include?("outdoor")
    return "serene park" if text.include?("park")
    return "quiet forest" if text.include?("forest") || text.include?("woods")
    return "sandy beach" if text.include?("beach")
    return "mountain landscape" if text.include?("mountain")

    # Default fallback
    text.include?("outdoor") ? "outdoor setting" : "indoor room"
  end

  def extract_lighting_conditions(location_text)
    text = location_text.to_s.downcase

    return "warm golden lighting" if text.include?("warm") || text.include?("cozy")
    return "bright natural lighting" if text.include?("bright") || text.include?("sunny")
    return "soft ambient lighting" if text.include?("soft") || text.include?("gentle")
    return "dramatic lighting" if text.include?("dramatic")
    return "dim atmospheric lighting" if text.include?("dim") || text.include?("dark")

    "warm lighting"  # default
  end

  def extract_architectural_details(location_text)
    text = location_text.to_s.downcase
    details = []

    details << "wooden floors" if text.include?("wood") || text.include?("wooden")
    details << "large windows" if text.include?("window")
    details << "high ceilings" if text.include?("high ceiling")
    details << "exposed beams" if text.include?("beam")
    details << "brick walls" if text.include?("brick")
    details << "stone elements" if text.include?("stone")

    details.any? ? details.join(", ") : nil
  end

  def extract_atmospheric_elements(location_text)
    text = location_text.to_s.downcase
    elements = []

    elements << "cozy atmosphere" if text.include?("cozy")
    elements << "peaceful ambiance" if text.include?("peaceful") || text.include?("calm")
    elements << "romantic mood" if text.include?("romantic")
    elements << "energetic vibe" if text.include?("energetic") || text.include?("lively")
    elements << "mysterious atmosphere" if text.include?("mysterious") || text.include?("dark")

    elements.any? ? elements.join(", ") : "comfortable atmosphere"
  end

  def extract_color_palette(location_text)
    text = location_text.to_s.downcase

    return "warm earth tones" if text.include?("warm") || text.include?("cozy")
    return "cool blue tones" if text.include?("cool") || text.include?("blue")
    return "neutral colors" if text.include?("neutral") || text.include?("minimal")
    return "vibrant colors" if text.include?("vibrant") || text.include?("colorful")
    return "pastel colors" if text.include?("pastel") || text.include?("soft")

    nil  # Let the AI decide if not specified
  end

  def extract_furniture_objects(location_text)
    text = location_text.to_s.downcase
    objects = []

    objects << "comfortable sofa" if text.include?("sofa") || text.include?("couch")
    objects << "wooden table" if text.include?("table")
    objects << "bookshelf" if text.include?("book") || text.include?("shelf")
    objects << "desk and chair" if text.include?("desk") || text.include?("office")
    objects << "bed" if text.include?("bed")
    objects << "plants" if text.include?("plant") || text.include?("green")

    objects.any? ? objects.join(", ") : nil
  end

  def extract_time_of_day(location_text)
    text = location_text.to_s.downcase

    return "morning" if text.include?("morning")
    return "afternoon" if text.include?("afternoon")
    return "evening" if text.include?("evening")
    return "night" if text.include?("night")
    return "sunset" if text.include?("sunset")
    return "dawn" if text.include?("dawn")

    nil  # Let context determine if not specified
  end

  def extract_weather_conditions(location_text)
    text = location_text.to_s.downcase

    return "sunny weather" if text.include?("sunny") || text.include?("bright")
    return "rainy weather" if text.include?("rain") || text.include?("storm")
    return "cloudy weather" if text.include?("cloud")
    return "snowy weather" if text.include?("snow")

    nil  # Indoor settings don't need weather
  end

  private

  def set_default_attributes
    self.pose_style ||= "standing pose, full body portrait"
    self.art_style_notes ||= "visual novel character art, anime art style, high quality, detailed"
  end

  def build_comprehensive_character_description(character)
    # Extract detailed description from character's description or tags
    base_desc = character.description.to_s

    # If description is too short, enhance with character tags
    if base_desc.length < 50 && character.tag_list.any?
      enhanced_desc = "#{base_desc} #{character.tag_list.join(", ")}"
      return enhanced_desc
    end

    base_desc
  end
end
