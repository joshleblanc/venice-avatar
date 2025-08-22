class ConversationsController < ApplicationController
  before_action :set_conversation, only: [:show]
  before_action :set_character, only: [:create]

  def index
    authorize Conversation
    @conversations = policy_scope(Conversation).where(user: current_user).includes(:character).order(updated_at: :desc)
  end

  def show
    # Filter out hidden messages (like appearance questions/responses) from user view
    @messages = @conversation.messages.where(
      "metadata IS NULL OR metadata->>'hidden' IS NULL OR metadata->>'hidden' != 'true'"
    ).order(:created_at)

    # Load available image styles for per-conversation override
    begin
      styles = FetchImageStylesJob.perform_now(Current.user)
      @image_styles = styles.map { |style| [style, style] }
      @image_styles << ["Default", ""]
    rescue => e
      Rails.logger.error "Failed to fetch image styles for conversation: #{e.message}"
      @image_styles = [["Default", ""]]
    end

    @selected_image_style = @conversation.metadata&.dig("image_style_override") || @conversation.user.image_style

    # Generate initial scene image if needed
    # if @conversation.scene_image.blank?
    #   initialize_conversation_scene
    # end
  end

  def regenerate_scene
    @conversation = Conversation.find(params[:id])
    authorize @conversation

    GenerateImagesJob.perform_later(@conversation)

    respond_to do |format|
      format.html { redirect_to @conversation, notice: "Regenerating scene image" }
      format.turbo_stream { head :ok }
      format.json { head :accepted }
    end
  end

  def image_style
    @conversation = Conversation.find(params[:id])
    authorize @conversation

    style = params.require(:conversation).permit(:image_style)[:image_style]
    metadata = @conversation.metadata || {}
    metadata["image_style_override"] = style.presence
    @conversation.update!(metadata: metadata)

    respond_to do |format|
      format.html { redirect_to @conversation, notice: "Updated image style" }
      format.turbo_stream { head :ok }
      format.json { head :ok }
    end
  end

  def create
    authorize Conversation
    @conversation = Conversation.new(character: @character)
    @conversation.user = current_user
    @conversation.generating_reply = true

    if @conversation.save
      InitializeSceneJob.perform_later(@conversation)
      redirect_to @conversation
    else
      redirect_to root_path, alert: "Failed to create conversation"
    end
  end

  def destroy
    conversation = Conversation.find(params[:id])
    authorize conversation
    conversation.destroy!

    respond_to do |format|
      format.html { redirect_to conversations_path, notice: "Conversation deleted" }
      format.json { head :no_content }
    end
  end

  private

  def set_conversation
    @conversation = Conversation.find(params[:id])
    authorize @conversation
  end

  def set_character
    @character = Character.find(params[:character_id])
    authorize @character
  end
end
