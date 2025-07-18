class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  discard_on ActiveJob::DeserializationError
  discard_on VeniceClient::ApiError

  def then(job)
    ActiveJob.perform_all_later(job)
  end
end
