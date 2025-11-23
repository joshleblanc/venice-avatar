class ImagePromptBuilder
  def initialize(conversation, appearance:, location:, action:)
    @conversation = conversation
    @character = conversation.character
    @appearance = squash(appearance)
    @location = squash(location)
    @action = squash(action)
  end

  def build
    return nil if [@appearance, @location, @action].all?(&:blank?)

    parts = []
    parts << @apperance if @appearance.present? #ensure_adult_prefix(@appearance) if @appearance.present?
    parts << @action if @action.present?
    parts << @location if @location.present?
    parts << "high detail, coherent lighting, consistent character" # anchor style/consistency without letting the model improvise

    prompt = parts.compact.join(", ")
    limit = @conversation.user&.prompt_limit || 1500
    prompt[0...limit].strip
  end

  private

  def squash(text)
    text.to_s.gsub(/\s+/, " ").strip
  end

  def ensure_adult_prefix(text)
    return text if text.blank?
    return text if text =~ /\badult\b/i

    "Adult #{text}"
  end
end
