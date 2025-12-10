# QueueVideoJob
#
# Queues a video generation request with the Venice API
# and schedules polling for completion.
#
class QueueVideoJob < ApplicationJob
  queue_as :default

  def perform(conversation, duration: "5s", resolution: "720p")
    service = VideoGenerationService.new(conversation)
    video_generation = service.queue(duration: duration, resolution: resolution)

    return unless video_generation&.queued?

    # Schedule the first status poll after a delay
    # Video generation typically takes 2-3 minutes
    PollVideoStatusJob.set(wait: 30.seconds).perform_later(video_generation)
  end
end
