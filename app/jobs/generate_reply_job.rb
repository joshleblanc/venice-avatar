class GenerateReplyJob < ApplicationJob
  queue_as :default

  def perform(conversation, user_message)
    # Generate chat response asynchronously
    GenerateChatResponseJob.perform_later(conversation, user_message)
  end
end
