class MessagesController < ApplicationController
  before_action :set_conversation, only: [:create]
  before_action :set_message, only: [:edit, :update, :destroy, :regenerate]

  def create
    @message = @conversation.messages.build(content: message_params[:content], role: "user", user: current_user)
    authorize @message
    if @message.save
      # Check if character is away - if so, queue the user message but don't generate reply yet
      if @conversation.character_away?
        Rails.logger.info "Character is away, queuing user message for conversation #{@conversation.id}"
        # Don't generate a reply - character will process all queued messages when they return
      else
        # Normal message flow - generate reply immediately
        GenerateReplyJob.perform_later(@conversation, @message)
      end
      respond_to do |format|
        format.html { redirect_to @conversation }
        format.turbo_stream {
          render turbo_stream: [
                   turbo_stream.append("messages", partial: "messages/message", locals: {
                                                     message: @message,
                                                   }),
                 ]
        }
      end
    else
      redirect_to @conversation, alert: "Failed to send message"
    end
  end

  def edit
    authorize @message
  end

  def update
    authorize @message
    if @message.update(message_params)
      redirect_to @message.conversation, notice: "Message updated successfully"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @message
    conversation = @message.conversation
    @message.destroy
    respond_to do |format|
      format.turbo_stream {
        render turbo_stream: turbo_stream.remove("message_#{@message.id}")
      }
      format.html { redirect_to conversation, notice: "Message deleted successfully" }
    end
  end

  def regenerate
    authorize @message
    return redirect_to @message.conversation, alert: "Can only regenerate assistant messages" unless @message.role == "assistant"
    return redirect_to @message.conversation, alert: "Can only regenerate the most recent message" unless @message == @message.conversation.messages.last

    # Find the previous user message to use as context
    previous_user_message = @message.conversation.messages
                                    .where(role: "user")
                                    .where("created_at < ?", @message.created_at)
                                    .order(created_at: :desc)
                                    .first

    # Delete the current assistant message
    @message.destroy

    # Generate a new reply
    if previous_user_message
      GenerateReplyJob.perform_later(@message.conversation, previous_user_message)
    end

    respond_to do |format|
      format.turbo_stream {
        render turbo_stream: turbo_stream.remove("message_#{@message.id}")
      }
      format.html { redirect_to @message.conversation, notice: "Regenerating response..." }
    end
  end

  private

  def set_conversation
    @conversation = Conversation.find(params[:conversation_id])
    authorize @conversation
  end

  def set_message
    @message = Message.find(params[:id])
  end

  def message_params
    params.require(:message).permit(:content)
  end
end
