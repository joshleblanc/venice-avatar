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

    # Generate initial scene image if needed
    # if @conversation.scene_image.blank?
    #   initialize_conversation_scene
    # end
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
