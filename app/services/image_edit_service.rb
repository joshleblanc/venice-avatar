# frozen_string_literal: true

# ImageEditService
#
# Handles image-to-image refinement for scene updates.
# Uses the existing scene image as a base and applies targeted edits
# based on conversation changes. This preserves character consistency
# better than regenerating from scratch.
#
# Best used for:
# - Minor clothing changes
# - Expression changes
# - Small pose adjustments
# - Background refinements
#
# Should NOT be used for:
# - Major location changes
# - Complete outfit changes
# - Initial scene generation
#
class ImageEditService
  # Change types that benefit from img2img vs full regeneration
  EDIT_SUITABLE_CHANGES = %w[
    expression
    minor_clothing
    accessory
    hair_adjustment
    pose_adjustment
    lighting
  ].freeze

  REGENERATE_CHANGES = %w[
    location
    major_clothing
    character_away
    time_of_day
    weather
  ].freeze

  def initialize(conversation)
    @conversation = conversation
    @character = conversation.character
    @consistency_service = CharacterConsistencyService.new(conversation)
  end

  # Edit the current scene image based on conversation changes
  # @param change_description [String] What changed in the scene
  # @param message_timestamp [Time] When the change occurred
  # @return [ActiveStorage::Attachment, nil] The edited scene image
  def edit_scene_image(change_description, message_timestamp = nil)
    unless can_edit?
      Rails.logger.info "Cannot use image editing, falling back to full generation"
      return nil
    end

    Rails.logger.info "Attempting image edit for scene refinement"

    edit_prompt = build_edit_prompt(change_description)
    base64_source = get_current_image_base64

    return nil if base64_source.blank?

    begin
      edited_base64 = EditImageJob.perform_now(
        @conversation.user,
        base64_source,
        edit_prompt
      )

      if edited_base64
        attach_edited_image(edited_base64)
        @conversation.scene_image
      else
        Rails.logger.warn "Image edit returned no data, falling back"
        nil
      end
    rescue => e
      Rails.logger.error "Image edit failed: #{e.message}"
      nil
    end
  end

  # Determine if a change is suitable for editing vs regeneration
  # @param change_type [String] Type of change detected
  # @return [Boolean] True if editing is recommended
  def should_edit?(change_type)
    return false unless can_edit?

    EDIT_SUITABLE_CHANGES.include?(change_type.to_s.downcase)
  end

  # Analyze conversation changes and determine change type
  # @return [String] Detected change type
  def detect_change_type
    old_appearance = @conversation.metadata&.dig("previous_appearance")
    old_location = @conversation.metadata&.dig("previous_location")
    old_action = @conversation.metadata&.dig("previous_action")

    current_appearance = @conversation.appearance
    current_location = @conversation.location
    current_action = @conversation.action

    # Location changed significantly
    if location_changed_significantly?(old_location, current_location)
      return "location"
    end

    # Major clothing change
    if major_clothing_change?(old_appearance, current_appearance)
      return "major_clothing"
    end

    # Minor adjustments
    if minor_appearance_change?(old_appearance, current_appearance)
      return "expression" # or minor_clothing
    end

    if pose_changed?(old_action, current_action)
      return "pose_adjustment"
    end

    "minor"
  end

  private

  def can_edit?
    # Can only edit if we have an existing scene image
    @conversation.scene_image.attached?
  end

  def get_current_image_base64
    return nil unless @conversation.scene_image.attached?

    begin
      blob = @conversation.scene_image.blob
      blob.download
      Base64.strict_encode64(blob.download)
    rescue => e
      Rails.logger.error "Failed to get current image base64: #{e.message}"
      nil
    end
  end

  def build_edit_prompt(change_description)
    # Build a targeted edit prompt that focuses on what changed
    # while maintaining character consistency

    locked_features = @consistency_service.locked_appearance_tags

    prompt_parts = []

    # Include locked features to maintain consistency
    if locked_features.present?
      prompt_parts << "Maintain: #{locked_features}"
    end

    # Add the specific change
    prompt_parts << "Change: #{change_description}"

    # Add quality modifiers
    prompt_parts << "high quality, detailed, consistent character"

    prompt_parts.join(". ")
  end

  def attach_edited_image(base64_data)
    image_data = Base64.decode64(base64_data)
    string_io = StringIO.new(image_data)
    string_io.set_encoding(Encoding::BINARY)

    @conversation.scene_image.attach(
      io: string_io,
      filename: "scene_edited.png",
      content_type: "image/png"
    )

    Rails.logger.info "Attached edited scene image to conversation #{@conversation.id}"
  end

  def location_changed_significantly?(old_loc, new_loc)
    return true if old_loc.blank? && new_loc.present?
    return false if new_loc.blank?

    # Check for location keywords that indicate major change
    location_keywords = %w[
      room kitchen bedroom bathroom living office outside outdoor
      beach forest mountain city street park garden cafe restaurant
      bar club gym pool
    ]

    old_locations = extract_location_keywords(old_loc, location_keywords)
    new_locations = extract_location_keywords(new_loc, location_keywords)

    # If the primary location changed, it's significant
    (new_locations - old_locations).any? || (old_locations - new_locations).any?
  end

  def major_clothing_change?(old_app, new_app)
    return false if old_app.blank? || new_app.blank?

    # Major clothing keywords
    major_items = %w[
      dress shirt pants jeans skirt suit uniform naked nude
      swimsuit bikini underwear lingerie coat jacket
    ]

    old_items = extract_clothing_items(old_app, major_items)
    new_items = extract_clothing_items(new_app, major_items)

    # More than one major item changed
    (old_items ^ new_items).size > 1
  end

  def minor_appearance_change?(old_app, new_app)
    return true if old_app.blank? || new_app.blank?

    # Calculate similarity - if very similar, it's minor
    old_words = old_app.downcase.split(/\W+/).to_set
    new_words = new_app.downcase.split(/\W+/).to_set

    intersection = (old_words & new_words).size
    union = (old_words | new_words).size

    similarity = union > 0 ? intersection.to_f / union : 0

    # High similarity = minor change
    similarity > 0.7
  end

  def pose_changed?(old_action, new_action)
    return true if old_action.blank? != new_action.blank?
    return false if new_action.blank?

    pose_keywords = %w[
      standing sitting lying kneeling crouching leaning
      arms crossed hands raised pointing holding
    ]

    old_poses = extract_location_keywords(old_action, pose_keywords)
    new_poses = extract_location_keywords(new_action, pose_keywords)

    old_poses != new_poses
  end

  def extract_location_keywords(text, keywords)
    return [] if text.blank?

    text_lower = text.downcase
    keywords.select { |kw| text_lower.include?(kw) }.to_set
  end

  def extract_clothing_items(text, items)
    return [] if text.blank?

    text_lower = text.downcase
    items.select { |item| text_lower.include?(item) }.to_set
  end
end
