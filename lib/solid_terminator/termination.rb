# frozen_string_literal: true

module SolidTerminator
  class Termination < SolidQueue::Record
    self.table_name = 'solid_queue_terminations'

    validates :active_job_id, presence: true, uniqueness: true

    scope :for_jobs, ->(job_ids) { where(active_job_id: job_ids) }
  end
end
