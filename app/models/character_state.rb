class CharacterState < ApplicationRecord
  belongs_to :conversation, touch: true

  # Active Storage attachments for generated images
  has_one_attached :character_image
  has_one_attached :background_image

  validates :conversation_id, presence: true

  # Character appearance tracking
  # JSON columns handle serialization automatically

  # Image URLs for generated content
  validates :background_image_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true }
  validates :character_image_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), allow_blank: true }

  scope :recent, -> { order(created_at: :desc) }

  # Initialize detailed character attributes with defaults
  after_initialize :set_default_attributes, if: :new_record?

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
      prompt_parts << "wearing #{clothing_details['latest_change']}"
    elsif default_outfit.present?
      prompt_parts << format_default_outfit
    end
    
    # Add injury details if present
    if injury_details.present? && injury_details["latest_injury"]
      prompt_parts << "showing #{injury_details['latest_injury']}"
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

  private

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
    
    eye_details["color"] ? "#{eye_details['color']} eyes" : ""
  end

  def format_distinctive_features
    return "" unless distinctive_features.present? && distinctive_features["features"]
    
    features = distinctive_features["features"]
    features.any? ? "with #{features.join(', ')}" : ""
  end

  def format_default_outfit
    return "" unless default_outfit.present?
    
    default_outfit["type"] ? "wearing #{default_outfit['type']}" : ""
  end
end
