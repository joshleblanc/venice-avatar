class GenerateCharacterJob < ApplicationJob
  after_discard do |job, exception|
    character = job.arguments.first
    character&.destroy if character&.persisted?
  end

  def perform(character, user, similar_characters = [])
    @character = character
    @user = user
    @similar_characters = similar_characters

    Rails.logger.info "Generating automatic character"

    # Generate character concept using AI
    character_concept = generate_character_concept

    character.assign_attributes({
      name: character_concept[:name],
      description: character_concept[:description],
      slug: generate_unique_slug(character_concept[:name]),
    })

    embedding = GenerateEmbeddingJob.perform_now(@user, "#{character.name}: #{character.description}")
    character.embedding = embedding
    character.save!

    similar_character = Character.nearest_neighbors(:embedding, embedding, distance: "cosine").first
    if similar_character.present? && similar_character.neighbor_distance < 0.5 && similar_character != character
      @similar_characters << "#{similar_character.name}: #{similar_character.description}"
      return GenerateCharacterJob.perform_now(@character, @user, @similar_characters)
    end

    GenerateCharacterAppearanceJob.perform_later(character, @user)

    # Generate detailed personality instructions
    CharacterInstructionGeneratorJob.perform_later(character, @user)
    Rails.logger.info "Auto-generated character: #{character.name}"
    character
  end

  private

  def generate_character_concept
    prompt = build_character_concept_prompt

    begin
      content = ChatCompletionJob.perform_now(@user, [{ role: "user", content: prompt }], { temperature: 0.9 })
      parse_character_concept(content)
    rescue => e
      Rails.logger.error "Failed to generate character concept: #{e.message}"
      # Fallback to predefined concepts
      generate_fallback_character_concept
    end
  end

  def build_character_concept_prompt
    # Get a diverse set of existing names to avoid repetition
    existing_names = Character.user_created.where(user: @user).pluck(:name).map { |name| name&.split&.first }.compact.uniq.last(20)

    <<~PROMPT
      Generate a unique and interesting character concept for a roleplay AI. Create someone with depth and personality that would be engaging to talk to.

      IMPORTANT NAMING REQUIREMENTS:
      - Use diverse, culturally varied names from different backgrounds
      - Avoid these recently used first names: #{existing_names.join(", ")}
      - Don't use fantasy/mystical names like "Zephyr", "Phoenix", "Luna", "Sage", "River" unless truly fitting
      - Consider common names from various cultures: Japanese, Spanish, Arabic, African, European, etc.
      - Mix of traditional and modern names
      - Examples:
        - Aiden Clarke
        - Bianca Rossi
        - Carlos Mendoza
        - Daria Ivanova
        - Elias Okafor
        - Fatima Zahid
        - Gianni Conti
        - Hiroshi Tanaka
        - Isabel Duarte
        - Jonas Bergstrom
        - Kamala Patel
        - Lukas Schneider
        - Marisol Alvarez
        - Nadia Petrovic
        - Omar Haddad
        - Priya Mehra
        - Quentin Dubois
        - Rosa Jimenez
        - Samuel Cohen
        - Tariq Khalil
        - Ursula Novak
        - Victor Hansen
        - Wei Zhang
        - Ximena Castillo
        - Yara Suleiman
        - Zoltan Kovacs

      DESCRIPTION REQUIREMENTS:
      - Avoid formulaic patterns like "Former X turned Y" or "Known for their Z"
      - Don't start with character archetype descriptions
      - Focus on specific, concrete details rather than vague traits
      - Include unexpected combinations of interests or backgrounds
      - Show personality through specific behaviors, not just adjectives
      - Avoid overused professions like "wandering poet", "mysterious librarian", "former pilot"
      - Examples:
        - Grew up in a coastal town repairing fishing nets with a grandfather. Studied marine biology but dropped out to run a community sailing program for underprivileged kids.
        - Second-generation baker from Naples whose family shop nearly collapsed during the pandemic. Rebuilt it with modern twists—selling focaccia on TikTok turned into a minor local celebrity.
        - Former professional cyclist sidelined by an injury, now a postal worker who secretly maps out the best bike routes in the city and shares them online under a pseudonym.
        - Once a competitive pianist, but stage fright derailed the career. Now restores antique instruments, convinced every piano has a memory of its players.
        - Trained as an architect, but turned to activism after a flood destroyed the neighborhood. Works on affordable housing initiatives and teaches carpentry to teens.
        - Born in Casablanca, worked as a translator for a human rights NGO. Keeps a diary in five languages, switching depending on mood.
        - Former paramedic in Rome, haunted by the one patient that couldn’t be saved. Volunteers as a crisis counselor on night shifts.
        - Retired bullet-train conductor who still wakes up at 4:30 a.m. every day. Collects miniature trains and is writing a memoir of the railway stories passengers told.
        - Grew up on a vineyard in Portugal. Left to become a software engineer but keeps a grandmother’s winemaking journal, planning to return and revive the land.
        - Once a rising hockey star in Sweden, became a wilderness guide after burning out from competition. Lives half the year in a cabin built by hand.

      CHARACTER VARIETY - Choose from diverse backgrounds:
      - Everyday people with interesting inner lives (accountant who writes horror novels, bus driver who collects vintage postcards)
      - Professionals with unexpected hobbies (surgeon who does stand-up comedy, teacher who restores classic cars)
      - People from different cultures and time periods
      - Characters with specific quirks, speech patterns, or unique perspectives
      - Mix introverts and extroverts, optimists and realists

      Avoid characters too similar to these existing ones:
      #{Character.order("RANDOM()").first(5).map { |c| "#{c.name}: #{c.description}" }.join("\n-----\n")}
      #{@similar_characters.join("\n-----\n") if @similar_characters.any?}

      Format your response exactly like this:
      Name: [Character Name]
      Description: [Character Description]

      Create someone genuinely unique and memorable!
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
