class ConversationsController < ApplicationController
  before_action :set_conversation, only: [:show, :send_message]
  before_action :set_character, only: [:create]

  def index
    @conversations = Conversation.includes(:character).order(updated_at: :desc)
  end

  def show
    @messages = @conversation.messages.order(:created_at)
    @current_state = @conversation.current_character_state
    
    # Generate initial images if needed
    if @current_state.nil?
      initialize_conversation_state
    end
  end

  def create
    @conversation = Conversation.new(character: @character)
    
    if @conversation.save
      initialize_conversation_state
      redirect_to @conversation
    else
      redirect_to root_path, alert: 'Failed to create conversation'
    end
  end

  def send_message
    user_message = params[:message]
    return redirect_to @conversation, alert: 'Message cannot be blank' if user_message.blank?

    # Save user message
    @conversation.messages.create!(content: user_message, role: 'user')

    # Analyze context and update character state
    context_tracker = ContextTrackerService.new(@conversation)
    new_state = context_tracker.analyze_message_context(user_message, 'user')

    # Send message to Venice API
    begin
      chat_response = send_to_venice_chat(user_message)
      
      # Save assistant response
      @conversation.messages.create!(content: chat_response, role: 'assistant')
      
      # Analyze assistant response for context changes
      assistant_state = context_tracker.analyze_message_context(chat_response, 'assistant')
      
      # Generate images for the latest state
      current_state = @conversation.current_character_state
      if current_state
        GenerateImagesJob.perform_later(@conversation.id, current_state.id)
      end

      # Update conversation timestamp
      @conversation.touch

      respond_to do |format|
        format.html { redirect_to @conversation }
        format.turbo_stream {
          render turbo_stream: [
            turbo_stream.append("messages", partial: "messages/message", locals: { 
              message: @conversation.messages.user_messages.last 
            }),
            turbo_stream.append("messages", partial: "messages/message", locals: { 
              message: @conversation.messages.assistant_messages.last 
            }),
            turbo_stream.replace("character-display", partial: "conversations/character_display", locals: { 
              conversation: @conversation, current_state: current_state 
            })
          ]
        }
      end

    rescue => e
      Rails.logger.error "Venice API error: #{e.message}"
      redirect_to @conversation, alert: 'Failed to send message to character'
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
      triggered_by_role: "system"
    )

    # Generate initial images
    GenerateImagesJob.perform_later(@conversation.id, initial_state.id)
  end

  def send_to_venice_chat(message)
    chat_api = VeniceClient::ChatApi.new
    
    # Build conversation history for context
    messages = @conversation.messages.order(:created_at).map do |msg|
      {
        role: msg.role,
        content: msg.content
      }
    end

    # Add the new user message
    messages << { role: 'user', content: message }

    response = chat_api.chat({
      character: @conversation.character.slug,
      messages: messages,
      max_tokens: 500
    })

    response.data&.choices&.first&.message&.content || "I'm sorry, I couldn't respond right now."
  end
end
