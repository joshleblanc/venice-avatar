class CharactersController < ApplicationController
  before_action :set_character, only: %i[ show edit update destroy ]

  # GET /characters or /characters.json
  def index
    authorize Character
    @user_characters = policy_scope(Character.where(user_created: true).order(:name))
  end

  # GET /characters/1 or /characters/1.json
  def show
  end

  # GET /characters/new
  def new
    @character = Character.new
    authorize @character
  end

  # POST /characters/auto_generate
  def auto_generate
    authorize Character
    @character = Character.create(
      user_created: true,
      user: current_user,
      generating: true,
      scenario_context: params[:scenario_context]
    )
    GenerateCharacterJob.perform_later(@character, current_user)

    respond_to do |format|
      if @character
        format.html { redirect_to @character, notice: "Character is being generated!" }
        format.json { render :show, status: :created, location: @character }
      else
        format.html { redirect_to characters_path, alert: "Failed to generate character. Please try again." }
        format.json { render json: { error: "Failed to generate character" }, status: :unprocessable_entity }
      end
    end
  end

  # POST /characters/enhance_scenario
  def enhance_scenario
    authorize Character
    prompt_text = params[:prompt]
    character_name = params[:name]
    character_description = params[:description]

    if prompt_text.blank?
      render json: { error: "Prompt cannot be empty" }, status: :unprocessable_entity
      return
    end

    begin
      enhanced_scenario = generate_enhanced_scenario(prompt_text, character_name, character_description)
      render json: { 
        scenario: enhanced_scenario[:scenario],
        character_name: enhanced_scenario[:character_name]
      }
    rescue => e
      Rails.logger.error "Failed to enhance scenario: #{e.message}"
      render json: { error: "Failed to enhance scenario. Please try again." }, status: :internal_server_error
    end
  end

  # POST /characters/enhance_description
  def enhance_description
    authorize Character
    prompt_text = params[:prompt]
    character_name = params[:name]
    scenario_context = params[:scenario]

    if prompt_text.blank?
      render json: { error: "Prompt cannot be empty" }, status: :unprocessable_entity
      return
    end

    begin
      enhanced_description = generate_enhanced_description(prompt_text, character_name, scenario_context)
      render json: { 
        description: enhanced_description[:description],
        character_name: enhanced_description[:character_name]
      }
    rescue => e
      Rails.logger.error "Failed to enhance description: #{e.message}"
      render json: { error: "Failed to enhance description. Please try again." }, status: :internal_server_error
    end
  end

  # GET /characters/1/edit
  def edit
  end

  # POST /characters or /characters.json
  def create
    authorize Character
    @character = Character.new(character_params)
    @character.user_created = true
    @character.slug = generate_unique_slug(@character.name)
    @character.user = current_user

    respond_to do |format|
      if @character.save
        CharacterInstructionGeneratorJob.perform_later(@character, current_user)
        @character.generate_appearance_later(current_user)

        format.html { redirect_to @character, notice: "Character was successfully created." }
        format.json { render :show, status: :created, location: @character }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @character.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /characters/1 or /characters/1.json
  def update
    respond_to do |format|
      if @character.update(character_params)
        format.html { redirect_to @character, notice: "Character was successfully updated." }
        format.json { render :show, status: :ok, location: @character }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @character.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /characters/1 or /characters/1.json
  def destroy
    @character.destroy!

    respond_to do |format|
      format.html { redirect_to characters_path, status: :see_other, notice: "Character was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_character
    @character = Character.find(params.expect(:id))
    authorize @character
  end

  # Only allow a list of trusted parameters through.
  def character_params
    params.expect(character: [:adult, :external_created_at, :description, :name, :share_url, :slug, :stats, :external_updated_at, :web_enabled, :scenario_context])
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

  def generate_enhanced_description(prompt_text, character_name = nil, scenario_context = nil)
    context_section = ""
    
    if character_name.present? || scenario_context.present?
      context_section = "\n\nEXISTING CHARACTER INFORMATION:"
      context_section += "\nCharacter Name: #{character_name}" if character_name.present?
      context_section += "\nScenario Context: #{scenario_context}" if scenario_context.present?
      context_section += "\n\nIMPORTANT: Use this existing information to create a character description that fits the name and scenario. The description should complement and enhance what's already defined."
    end

    enhancement_prompt = <<~PROMPT
      You are a creative character designer for roleplay AI. The user has provided a brief character idea, and you need to expand it into a detailed, engaging character description.

      User's prompt: "#{prompt_text}"#{context_section}

      Create a detailed character description based on this prompt. The description should:
      1. Define the character's background, personality, and key traits
      2. Include specific, concrete details that make the character unique and memorable
      3. Describe their interests, quirks, and what makes them engaging to interact with
      4. Be appropriate for adult roleplay (18+)
      5. Match the tone and style implied by the user's prompt
      6. Be written in a narrative style that brings the character to life
      #{character_name.present? || scenario_context.present? ? "7. Incorporate and build upon the existing character information provided above" : ""}

      IMPORTANT: Focus on WHO the character is - their personality, background, interests, and what makes them unique. Write in third person or as a character profile.

      #{character_name.present? ? "Use the character name '#{character_name}' in the description." : "If the prompt mentions a specific name, extract it. Otherwise, suggest an appropriate name."}

      Format your response exactly like this:
      CHARACTER_NAME: [Name of the character]
      DESCRIPTION: [The detailed character description]

      Example:
      CHARACTER_NAME: Marcus Chen
      DESCRIPTION: Marcus is a former street artist turned art therapist who uses creativity to help people process difficult emotions. At 32, he has an easygoing confidence that comes from years of navigating both the underground art scene and formal psychology training. He's passionate about finding beauty in unexpected places and believes that everyone has an artist inside them waiting to be discovered. Marcus has a habit of sketching on napkins during conversations and often speaks in visual metaphors. He's warm and encouraging, with a playful sense of humor that helps people feel comfortable opening up. His studio apartment is filled with half-finished canvases and plants he's named after famous artists.

      Make it vivid and true to the user's vision!
    PROMPT

    response = ChatCompletionJob.perform_now(
      current_user,
      [{ role: "user", content: enhancement_prompt }],
      { temperature: 0.8 }
    )

    content = response.content.strip
    
    # Parse the response
    character_name = nil
    description = nil

    lines = content.split("\n")
    current_section = nil

    lines.each do |line|
      if line.start_with?("CHARACTER_NAME:")
        character_name = line.sub("CHARACTER_NAME:", "").strip
        current_section = :character_name
      elsif line.start_with?("DESCRIPTION:")
        description = line.sub("DESCRIPTION:", "").strip
        current_section = :description
      elsif current_section == :description && line.strip.present?
        description += "\n" + line
      end
    end

    {
      description: description&.strip || content,
      character_name: character_name
    }
  end

  def generate_enhanced_scenario(prompt_text, character_name = nil, character_description = nil)
    context_section = ""
    
    if character_name.present? || character_description.present?
      context_section = "\n\nEXISTING CHARACTER INFORMATION:"
      context_section += "\nCharacter Name: #{character_name}" if character_name.present?
      context_section += "\nCharacter Description: #{character_description}" if character_description.present?
      context_section += "\n\nIMPORTANT: Use this existing character information to create a scenario that fits THIS specific character. The scenario should complement and enhance what's already defined about the character."
    end

    enhancement_prompt = <<~PROMPT
      You are a creative scenario generator for roleplay AI characters. The user has provided a brief prompt, and you need to expand it into a detailed scenario description that will be used to create a character.

      User's prompt: "#{prompt_text}"#{context_section}

      Create a detailed scenario based on this prompt. The scenario should:
      1. Be vivid and immersive with specific details about the setting, atmosphere, and situation
      2. Define the AI character's role, personality, and context within this scenario
      3. Describe what makes this character interesting and engaging for this specific scenario
      4. Set up the situation and dynamic that the character will be part of
      5. Be appropriate for adult roleplay (18+)
      6. Match the tone and genre implied by the user's prompt
      #{character_name.present? || character_description.present? ? "7. Incorporate and build upon the existing character information provided above" : ""}

      IMPORTANT: Focus on defining the CHARACTER and their context. Do NOT define the user's role - the scenario should be written from the perspective of "this is the character you'll be interacting with in this setting."

      #{character_name.present? ? "Use the character name '#{character_name}' in the scenario." : "If the prompt mentions a specific character name or role, extract it. Otherwise, suggest an appropriate name/role."}

      Format your response exactly like this:
      CHARACTER_NAME: [Name or role of the AI character]
      SCENARIO: [The detailed scenario description focused on the character and their context]

      Example:
      CHARACTER_NAME: Sofia
      SCENARIO: Sofia is a charismatic bartender who runs the rooftop bar "Skyline" in the heart of the city. The setting is intimate and atmospheric - warm string lights cast a golden glow over the polished bar, and the city skyline stretches out behind her. She's known for her creative cocktails and her ability to make every patron feel like they're the only person in the room. Tonight, the air is warm with a hint of spice from her latest creation, and smooth jazz plays softly in the background. Sofia has a magnetic presence, confident and flirtatious, with a genuine warmth that draws people in.

      Make it engaging and true to the user's vision!
    PROMPT

    response = ChatCompletionJob.perform_now(
      current_user,
      [{ role: "user", content: enhancement_prompt }],
      { temperature: 0.8 }
    )

    content = response.content.strip
    
    # Parse the response
    character_name = nil
    scenario = nil

    lines = content.split("\n")
    current_section = nil

    lines.each do |line|
      if line.start_with?("CHARACTER_NAME:")
        character_name = line.sub("CHARACTER_NAME:", "").strip
        current_section = :character_name
      elsif line.start_with?("SCENARIO:")
        scenario = line.sub("SCENARIO:", "").strip
        current_section = :scenario
      elsif current_section == :scenario && line.strip.present?
        scenario += "\n" + line
      end
    end

    {
      scenario: scenario&.strip || content,
      character_name: character_name
    }
  end
end
