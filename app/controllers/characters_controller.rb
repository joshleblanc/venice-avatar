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

    if prompt_text.blank?
      render json: { error: "Prompt cannot be empty" }, status: :unprocessable_entity
      return
    end

    begin
      enhanced_scenario = generate_enhanced_scenario(prompt_text)
      render json: { 
        scenario: enhanced_scenario[:scenario],
        character_name: enhanced_scenario[:character_name],
        user_role: enhanced_scenario[:user_role]
      }
    rescue => e
      Rails.logger.error "Failed to enhance scenario: #{e.message}"
      render json: { error: "Failed to enhance scenario. Please try again." }, status: :internal_server_error
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

  def generate_enhanced_scenario(prompt_text)
    enhancement_prompt = <<~PROMPT
      You are a creative scenario generator for roleplay AI characters. The user has provided a brief prompt, and you need to expand it into a detailed, engaging scenario.

      User's prompt: "#{prompt_text}"

      Create a detailed scenario based on this prompt. The scenario should:
      1. Be vivid and immersive with specific details about the setting, atmosphere, and situation
      2. Include clear character roles - identify who the AI character is and who the user is in this scenario
      3. Set up an interesting dynamic or situation that invites interaction
      4. Be appropriate for adult roleplay (18+)
      5. Match the tone and genre implied by the user's prompt

      IMPORTANT: If the prompt mentions specific characters or roles, clearly identify:
      - CHARACTER_NAME: The name/role of the AI character in this scenario
      - USER_ROLE: The name/role of the user in this scenario

      Format your response exactly like this:
      CHARACTER_NAME: [Name or role of the AI character, or "Not specified" if the scenario doesn't define specific characters]
      USER_ROLE: [Name or role of the user, or "Not specified" if not defined]
      SCENARIO: [The detailed scenario description]

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
    user_role = nil
    scenario = nil

    lines = content.split("\n")
    current_section = nil

    lines.each do |line|
      if line.start_with?("CHARACTER_NAME:")
        character_name = line.sub("CHARACTER_NAME:", "").strip
        current_section = :character_name
      elsif line.start_with?("USER_ROLE:")
        user_role = line.sub("USER_ROLE:", "").strip
        current_section = :user_role
      elsif line.start_with?("SCENARIO:")
        scenario = line.sub("SCENARIO:", "").strip
        current_section = :scenario
      elsif current_section == :scenario && line.strip.present?
        scenario += "\n" + line
      end
    end

    # Clean up "Not specified" values
    character_name = nil if character_name&.downcase&.include?("not specified")
    user_role = nil if user_role&.downcase&.include?("not specified")

    {
      scenario: scenario&.strip || content,
      character_name: character_name,
      user_role: user_role
    }
  end
end
