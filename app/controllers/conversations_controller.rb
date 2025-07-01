class ConversationsController < ApplicationController
  before_action :set_conversation, only: [:show, :send_message]
  before_action :set_character, only: [:create]

  def index
    @conversations = Conversation.includes(:character).order(updated_at: :desc)
  end

  def show
    @messages = @conversation.messages.order(:created_at)

    # Generate initial scene image if needed
    if @conversation.scene_image.blank?
      initialize_conversation_scene
    end
  end

  def create
    @conversation = Conversation.new(character: @character)

    if @conversation.save
      initialize_conversation_scene
      redirect_to @conversation
    else
      redirect_to root_path, alert: "Failed to create conversation"
    end
  end

  def send_message
    user_message = params[:message]
    return redirect_to @conversation, alert: "Message cannot be blank" if user_message.blank?

    user_msg = @conversation.messages.create!(content: user_message, role: "user")

    # Check if character is away - if so, queue the user message but don't generate reply yet
    if @conversation.character_away?
      Rails.logger.info "Character is away, queuing user message for conversation #{@conversation.id}"
      # Don't generate a reply - character will process all queued messages when they return
    else
      # Normal message flow - generate reply immediately
      GenerateReplyJob.perform_later(@conversation, user_msg)
    end

    respond_to do |format|
      format.html { redirect_to @conversation }
      format.turbo_stream {
        render turbo_stream: [
          turbo_stream.append("messages", partial: "messages/message", locals: {
                                            message: user_msg,
                                          }),
        ]
      }
    end
  end

  private

  def set_conversation
    @conversation = Conversation.find(params[:id])
  end

  def set_character
    @character = Character.find(params[:character_id])
  end

  def initialize_conversation_scene
    InitializeSceneJob.perform_later(@conversation)
  end
end
