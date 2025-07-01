class ConversationsController < ApplicationController
  before_action :set_conversation, only: [:show, :send_message]
  before_action :set_character, only: [:create]

  def index
    @conversations = Conversation.includes(:character, :messages).order(updated_at: :desc)
  end

  def show
    @messages = @conversation.messages.order(:created_at)
    current_state = @conversation.current_character_state

    # Generate initial images if needed
    if current_state.nil?
      initialize_conversation_state
    end
  end

  def create
    @conversation = Conversation.new(character: @character)

    if @conversation.save
      initialize_conversation_state
      redirect_to @conversation
    else
      redirect_to root_path, alert: "Failed to create conversation"
    end
  end

  def send_message
    user_message = params[:message]
    return redirect_to @conversation, alert: "Message cannot be blank" if user_message.blank?

    user_msg = @conversation.messages.create!(content: user_message, role: "user")

    # Enqueue background job to generate reply
    GenerateReplyJob.perform_later(@conversation, user_msg)

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

  def initialize_conversation_state
    # Create initial character state
    initial_state = @conversation.character_states.create!(
      location: "A comfortable room",
      appearance_description: @conversation.character.description || "A friendly character",
      expression: "neutral",
      background_prompt: "A cozy indoor setting with warm lighting, visual novel style",
      message_context: "Initial conversation setup",
      triggered_by_role: "system",
    )

    # Generate initial images
    GenerateImagesJob.perform_later(@conversation, initial_state)
  end
end
