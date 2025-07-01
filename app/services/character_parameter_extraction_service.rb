class CharacterParameterExtractionService
  def initialize
    @venice_client = VeniceClient::ChatApi.new
  end

  def extract_parameters_from_description(character_description)
    # Build prompt for AI parameter extraction
    extraction_prompt = build_parameter_extraction_prompt(character_description)

    # Get AI analysis of the character description
    ai_response = request_parameter_extraction(extraction_prompt)

    # Log the AI response for debugging
    Rails.logger.info "Character Parameter Extraction Response: #{ai_response}"

    # Parse AI response into structured parameters
    parse_parameter_response(ai_response)
  end

  private

  def build_parameter_extraction_prompt(character_description)
    <<~PROMPT
      You are an expert at analyzing character descriptions for visual novel image generation. Extract detailed visual parameters from the following character description to ensure consistent and accurate image generation.

      CHARACTER DESCRIPTION:
      "#{character_description}"

      EXTRACTION REQUIREMENTS:
      Analyze the description and extract COMPLETE visual parameters for image generation. If specific details aren't mentioned, make reasonable assumptions based on the character's context and typical visual novel character designs.

      RESPONSE FORMAT (JSON):
      {
        "physical_features": {
          "age_appearance": "apparent age (young adult, teen, mature, etc.)",
          "height": "height description (tall, average, short, petite)",
          "build": "body build (slender, athletic, curvy, average build)"
        },
        "hair_details": {
          "length": "hair length (long, short, medium, shoulder-length)",
          "color": "hair color (black, brown, blonde, red, etc.)",
          "style": "hairstyle (straight, curly, wavy, braided, ponytail, etc.)",
          "texture": "hair texture if notable (silky, messy, etc.)"
        },
        "eye_details": {
          "color": "eye color (blue, green, brown, hazel, etc.)",
          "shape": "eye shape if distinctive (large, narrow, etc.)",
          "expression": "typical eye expression (gentle, sharp, sleepy, etc.)"
        },
        "body_details": {
          "body_type": "body type (slender, athletic, curvy, petite, average build)",
          "skin_tone": "skin tone (pale, fair, light, medium, tan, dark, olive)"
        },
        "distinctive_features": {
          "features": ["list of distinctive features like scars, tattoos, etc."],
          "accessories": ["glasses, jewelry, etc."]
        },
        "default_outfit": {
          "type": "clothing type (school uniform, casual wear, formal, etc.)",
          "description": "detailed outfit description",
          "colors": ["primary clothing colors"]
        },
        "personality_visual_cues": {
          "typical_expression": "default facial expression",
          "pose_style": "typical pose or stance",
          "demeanor": "visual personality indicators"
        },
        "art_style_notes": {
          "style": "visual novel character art, anime art style, high quality, detailed",
          "quality_tags": ["masterpiece", "best quality", "ultra detailed"],
          "composition": "full body portrait, standing pose"
        }
      }

      IMPORTANT GUIDELINES:
      1. Extract information directly from the description when available
      2. Make reasonable assumptions for missing details based on character context
      3. Ensure all fields have values - never leave empty or null
      4. Focus on visual elements that would be important for image generation
      5. Consider the character's role, personality, and setting when making assumptions
      6. Use standard visual novel/anime character design conventions
    PROMPT
  end

  def request_parameter_extraction(prompt)
    begin
      # Use the context analyzer character for consistency
      analyzer_character = ContextAnalyzerCharacterService.get_context_analyzer_character
      unless analyzer_character
        Rails.logger.error "Context analyzer character not available for parameter extraction"
        return fallback_extraction
      end

      response = @venice_client.create_chat_completion(
        body: {
          model: "venice-uncensored",
          messages: [
            { role: "system", content: "You are an expert visual analyst specializing in character design for visual novels. Extract detailed visual parameters from character descriptions with precision and consistency." },
            { role: "user", content: prompt },
          ],
        },
      )
      response.choices.first[:message][:content] || ""
    rescue => e
      Rails.logger.error "Character Parameter Extraction failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      # Fallback to basic extraction if AI fails
      fallback_extraction
    end
  end

  def parse_parameter_response(ai_response)
    begin
      # Try to extract JSON from the response
      json_match = ai_response.match(/\{.*\}/m)
      if json_match
        parsed = JSON.parse(json_match[0])
        normalize_parameter_response(parsed)
      else
        Rails.logger.error "No JSON found in parameter extraction response"
        fallback_extraction
      end
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse parameter extraction JSON: #{e.message}"
      Rails.logger.error "Raw response: #{ai_response}"
      fallback_extraction
    end
  end

  def normalize_parameter_response(parsed)
    # Ensure all required fields exist with defaults
    {
      physical_features: normalize_physical_features(parsed["physical_features"]),
      hair_details: normalize_hair_details(parsed["hair_details"]),
      eye_details: normalize_eye_details(parsed["eye_details"]),
      body_details: normalize_body_details(parsed["body_details"]),
      distinctive_features: normalize_distinctive_features(parsed["distinctive_features"]),
      default_outfit: normalize_default_outfit(parsed["default_outfit"]),
      personality_visual_cues: normalize_personality_cues(parsed["personality_visual_cues"]),
      art_style_notes: normalize_art_style(parsed["art_style_notes"])
    }
  end

  def normalize_physical_features(features)
    features ||= {}
    {
      "age_appearance" => features["age_appearance"] || "young adult",
      "height" => features["height"] || "average",
      "build" => features["build"] || "average build"
    }
  end

  def normalize_hair_details(hair)
    hair ||= {}
    {
      "length" => hair["length"] || "medium",
      "color" => hair["color"] || "brown",
      "style" => hair["style"] || "straight",
      "texture" => hair["texture"] || "smooth"
    }
  end

  def normalize_eye_details(eyes)
    eyes ||= {}
    {
      "color" => eyes["color"] || "brown",
      "shape" => eyes["shape"] || "normal",
      "expression" => eyes["expression"] || "gentle"
    }
  end

  def normalize_body_details(body)
    body ||= {}
    {
      "body_type" => body["body_type"] || "average build",
      "skin_tone" => body["skin_tone"] || "fair"
    }
  end

  def normalize_distinctive_features(features)
    features ||= {}
    {
      "features" => features["features"] || [],
      "accessories" => features["accessories"] || []
    }
  end

  def normalize_default_outfit(outfit)
    outfit ||= {}
    {
      "type" => outfit["type"] || "casual wear",
      "description" => outfit["description"] || "comfortable everyday clothing",
      "colors" => outfit["colors"] || ["neutral tones"]
    }
  end

  def normalize_personality_cues(cues)
    cues ||= {}
    {
      "typical_expression" => cues["typical_expression"] || "neutral",
      "pose_style" => cues["pose_style"] || "standing pose",
      "demeanor" => cues["demeanor"] || "approachable"
    }
  end

  def normalize_art_style(style)
    style ||= {}
    {
      "style" => style["style"] || "visual novel character art, anime art style, high quality, detailed",
      "quality_tags" => style["quality_tags"] || ["masterpiece", "best quality", "ultra detailed"],
      "composition" => style["composition"] || "full body portrait, standing pose"
    }
  end

  def fallback_extraction
    # Return basic default parameters if AI extraction fails
    {
      physical_features: {
        "age_appearance" => "young adult",
        "height" => "average",
        "build" => "average build"
      },
      hair_details: {
        "length" => "medium",
        "color" => "brown",
        "style" => "straight",
        "texture" => "smooth"
      },
      eye_details: {
        "color" => "brown",
        "shape" => "normal",
        "expression" => "gentle"
      },
      body_details: {
        "body_type" => "average build",
        "skin_tone" => "fair"
      },
      distinctive_features: {
        "features" => [],
        "accessories" => []
      },
      default_outfit: {
        "type" => "casual wear",
        "description" => "comfortable everyday clothing",
        "colors" => ["neutral tones"]
      },
      personality_visual_cues: {
        "typical_expression" => "neutral",
        "pose_style" => "standing pose",
        "demeanor" => "approachable"
      },
      art_style_notes: {
        "style" => "visual novel character art, anime art style, high quality, detailed",
        "quality_tags" => ["masterpiece", "best quality", "ultra detailed"],
        "composition" => "full body portrait, standing pose"
      }
    }
  end
end
