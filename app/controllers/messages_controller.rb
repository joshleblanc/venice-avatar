class MessagesController < ApplicationController
  before_action :set_conversation, only: [:create]

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

  private

  def set_conversation
    @conversation = Conversation.find(params[:conversation_id])
    authorize @conversation
  end

  def message_params
    params.require(:message).permit(:content)
  end
end
