class VideoGeneration < ApplicationRecord
  broadcasts_refreshes

  belongs_to :conversation, touch: true

  has_one_attached :video

  # Status constants
  PENDING = "pending".freeze
  QUEUED = "queued".freeze
  PROCESSING = "processing".freeze
  COMPLETED = "completed".freeze
  FAILED = "failed".freeze

  STATUSES = [PENDING, QUEUED, PROCESSING, COMPLETED, FAILED].freeze

  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: PENDING) }
  scope :queued, -> { where(status: QUEUED) }
  scope :processing, -> { where(status: PROCESSING) }
  scope :completed, -> { where(status: COMPLETED) }
  scope :failed, -> { where(status: FAILED) }
  scope :in_progress, -> { where(status: [QUEUED, PROCESSING]) }

  def pending?
    status == PENDING
  end

  def queued?
    status == QUEUED
  end

  def processing?
    status == PROCESSING
  end

  def completed?
    status == COMPLETED
  end

  def failed?
    status == FAILED
  end

  def in_progress?
    queued? || processing?
  end

  def progress_percentage
    return 0 if average_execution_time.nil? || average_execution_time.zero?
    return 100 if completed?

    [(execution_duration.to_f / average_execution_time * 100).round, 99].min
  end

  def estimated_time_remaining
    return 0 if completed? || average_execution_time.nil?

    remaining = average_execution_time - (execution_duration || 0)
    [remaining, 0].max
  end
end
