class CharactersController < ApplicationController
  before_action :set_character, only: %i[ show edit update destroy ]

  # GET /characters or /characters.json
  def index
    authorize Character
    @user_characters = policy_scope(Character.where(user_created: true).order(:name))
    @venice_characters = policy_scope(Character.where(user_created: false).order(:name))
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
    )
    GenerateCharacterJob.perform_later(@character)

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
        CharacterInstructionGeneratorJob.perform_later(@character)
        @character.generate_appearance_later

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
    params.expect(character: [:adult, :external_created_at, :description, :name, :share_url, :slug, :stats, :external_updated_at, :web_enabled])
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
