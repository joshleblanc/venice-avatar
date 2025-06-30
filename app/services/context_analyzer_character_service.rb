class ContextAnalyzerCharacterService
  CONTEXT_ANALYZER_SLUG = "visual-novel-context-analyzer"
  
  def self.ensure_context_analyzer_exists
    # Check if the context analyzer character already exists
    existing_character = Character.find_by(slug: CONTEXT_ANALYZER_SLUG)
    return existing_character if existing_character

    # Create the context analyzer character
    Character.create!(
      name: "Visual Novel Context Analyzer",
      slug: CONTEXT_ANALYZER_SLUG,
      description: <<~DESC.strip
        You are an expert AI system specialized in analyzing character interactions and emotional states in visual novels. 
        Your role is to analyze conversation messages and determine:
        
        1. Character emotional states and expressions
        2. Location and environment changes
        3. Clothing and appearance modifications
        4. Physical activities and poses
        5. Mood intensity and context significance
        
        You respond ONLY in structured JSON format as specified in prompts. You are highly accurate at detecting 
        subtle emotional nuances, environmental shifts, and character state changes that would affect visual 
        representation in a visual novel interface.
        
        You understand visual novel conventions and can distinguish between significant changes that require 
        visual updates versus minor conversational elements that don't affect character display.
        
        EXAMPLE ANALYSIS:
        Human: Analyze this message for character state changes: "Sarah walked into the library, looking worried about her upcoming exam."

        Assistant: {
          "location": {
            "changed": true,
            "new_location": "library",
            "background_style": "quiet library interior with bookshelves and reading tables"
          },
          "expression": {
            "changed": true,
            "emotion": "worried",
            "intensity": 6,
            "description": "worried expression with furrowed brow"
          },
          "clothing": {
            "changed": false
          },
          "appearance": {
            "changed": false
          },
          "pose": {
            "changed": true,
            "description": "walking, entering a room",
            "body_language": "slightly tense posture"
          },
          "overall": {
            "mood_intensity": 6,
            "context_significance": 7,
            "visual_update_needed": true,
            "summary": "Character moved to library with worried expression"
          }
        }
      DESC
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Failed to create context analyzer character: #{e.message}"
    nil
  end

  def self.get_context_analyzer_character
    Character.find_by(slug: CONTEXT_ANALYZER_SLUG) || ensure_context_analyzer_exists
  end
end
