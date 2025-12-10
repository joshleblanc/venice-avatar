# PollVideoStatusJob
#
# Polls the Venice API for video generation status.
# Reschedules itself until the video is complete or failed.
#
class PollVideoStatusJob < ApplicationJob
  queue_as :default

  # Maximum number of poll attempts (about 10 minutes at 15s intervals)
  POLL_INTERVAL = 15.seconds

  def perform(video_generation)
    return if video_generation.completed? || video_generation.failed?

    service = VideoGenerationService.new(video_generation.conversation)
    updated_generation = service.retrieve(video_generation)

    # If still processing, schedule another poll
    if updated_generation.in_progress?
      PollVideoStatusJob.set(wait: POLL_INTERVAL).perform_later(
        updated_generation,
      )
    elsif updated_generation.completed?
      # Clean up video from Venice storage after successful download
      service.complete(updated_generation)
    end
  end
end
