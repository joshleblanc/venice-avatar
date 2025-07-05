class GenerateCharacterJob < ApplicationJob
  def perform(character, similar_characters = [])
    @character = character
    @user = character.user
    @similar_characters = similar_characters

    Rails.logger.info "Generating automatic character"

    # Generate character concept using AI
    character_concept = generate_character_concept

    character.assign_attributes({
      name: character_concept[:name],
      description: character_concept[:description],
      slug: generate_unique_slug(character_concept[:name]),
    })

    embedding = GenerateEmbeddingJob.perform_now("#{character.name}: #{character.description}")
    character.embedding = embedding
    character.save!

    similar_character = Character.nearest_neighbors(:embedding, embedding, distance: "cosine").first
    if similar_character.present? && similar_character.neighbor_distance < 0.5 && similar_character != character
      @similar_characters << "#{similar_character.name}: #{similar_character.description}"
      GenerateCharacterJob.perform_later(@character, @similar_characters)
      return
    end

    # Generate detailed personality instructions
    CharacterInstructionGeneratorJob.perform_later(character)
    Rails.logger.info "Auto-generated character: #{character.name}"
    character
  end

  private

  def generate_character_concept
    prompt = build_character_concept_prompt

    begin
      content = ChatCompletionJob.perform_now(@user, [{ role: "user", content: prompt }], { max_completion_tokens: 500, temperature: 0.9 })
      parse_character_concept(content)
    rescue => e
      Rails.logger.error "Failed to generate character concept: #{e.message}"
      # Fallback to predefined concepts
      generate_fallback_character_concept
    end
  end

  def build_character_concept_prompt
    <<~PROMPT
      Generate a unique and interesting character concept for a roleplay AI. Create someone with depth and personality that would be engaging to talk to.

      Please provide:
      1. A name (first name and optionally last name)
      2. A brief but compelling description (2-3 sentences) that captures their essence, personality, background, or unique traits

      Make the character feel authentic and three-dimensional. They could be:
      - From any time period or setting (modern, historical, fantasy, sci-fi, etc.)
      - Any profession or background
      - Have interesting hobbies, quirks, or life experiences
      - Possess unique personality traits or perspectives

      Avoid characters that are too similar to the following:
      #{@similar_characters.map { |c| "#{c.name}: #{c.description}" }.join("\n")}

      Format your response exactly like this:
      Name: [Character Name]
      Description: [Character Description]

      Be creative and original!
    PROMPT
  end

  def parse_character_concept(content)
    lines = content.split("\n").map(&:strip).reject(&:empty?)

    name = nil
    description = nil

    lines.each do |line|
      if line.start_with?("Name:")
        name = line.sub("Name:", "").strip
      elsif line.start_with?("Description:")
        description = line.sub("Description:", "").strip
      end
    end

    # If parsing failed, try to extract from the content
    if name.nil? || description.nil?
      # Fallback parsing - look for patterns
      name_match = content.match(/Name:\s*(.+?)(?:\n|$)/i)
      desc_match = content.match(/Description:\s*(.+?)(?:\n\n|$)/mi)

      name = name_match[1].strip if name_match
      description = desc_match[1].strip if desc_match
    end

    # Final fallback if parsing completely failed
    if name.nil? || description.nil?
      return generate_fallback_character_concept
    end

    {
      name: name,
      description: description,
    }
  end

  def generate_fallback_character_concept
    # Predefined character concepts as fallback
    concepts = [
      {
        name: "Luna Blackwood",
        description: "A mysterious librarian who specializes in ancient texts and folklore. She has an uncanny ability to find exactly the book someone needs, even if they don't know they need it. Luna speaks in riddles sometimes and has a deep fascination with the stories people don't tell.",
      },
      {
        name: "Marcus Chen",
        description: "A former street artist turned art therapist who uses creativity to help people process difficult emotions. He's passionate about finding beauty in unexpected places and believes that everyone has an artist inside them waiting to be discovered.",
      },
      {
        name: "Sage Winters",
        description: "A traveling botanist and tea enthusiast who has spent years studying plants around the world. They have a greenhouse full of rare specimens and can tell you the perfect tea blend for any mood or situation. Sage speaks with gentle wisdom and always seems to know just what to say.",
      },
      {
        name: "River Nakamura",
        description: "A former competitive swimmer turned marine biologist who now studies ocean conservation. They have a deep connection to water and often speak in metaphors related to tides, currents, and the rhythm of the sea. River is passionate about protecting the environment.",
      },
      {
        name: "Phoenix Delacroix",
        description: "A reformed con artist who now works as a private investigator specializing in finding lost people. They have an exceptional ability to read people and situations, using their past experience to help others. Phoenix is charming but carries the weight of their complicated past.",
      },
    ]

    concepts.sample
  end

  def generate_unique_slug(name)
    base_slug = name.parameterize
    slug = base_slug
    counter = 1

    while Character.exists?(slug: slug)
      slug = "#{base_slug}-#{counter}"
      counter += 1
    end

    slug
  end
end
