# frozen_string_literal: true

module SolidQueue
  class TerminatedExecution < SolidQueue::Execution
    scope :ordered, -> { order(terminated_at: :desc) }

    def self.record_termination(active_job)
      sq_job = SolidQueue::Job.find_by(active_job_id: active_job.job_id)
      return nil unless sq_job

      create!(job_id: sq_job.id, queue_name: sq_job.queue_name, priority: sq_job.priority, terminated_at: Time.current)
    rescue StandardError => e
      SolidTerminator.configuration.logger.error(
        "Failed to record termination for job #{active_job.job_id}: #{e.class}: #{e.message}"
      )
      nil
    end

    def retry
      active_job = ActiveJob::Base.deserialize(job.arguments)
      transaction do
        destroy!
        active_job.enqueue
      end
    end
  end
end
