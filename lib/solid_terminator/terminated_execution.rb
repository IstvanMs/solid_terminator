# frozen_string_literal: true

module SolidQueue
  class TerminatedExecution < SolidQueue::Execution
    class NotRetryable < StandardError; end

    # Copied from the job so retry still works after SolidQueue clears the finished job.
    serialize :arguments, coder: JSON

    scope :ordered, -> { order(terminated_at: :desc) }

    # Without the column, `serialize` keeps arguments as a virtual attribute and saves silently drop them.
    def self.log_unless_migrated
      return if table_exists? && column_names.include?('arguments')

      SolidTerminator.configuration.logger.error(
        'solid_queue_terminated_executions is missing migrations, so terminated jobs cannot be retried. ' \
        'Run `bin/rails generate solid_terminator:update` and migrate.'
      )
    end

    def self.record_termination(active_job)
      sq_job = SolidQueue::Job.find_by(active_job_id: active_job.job_id)
      return nil unless sq_job

      log_unless_migrated

      create!(job_id: sq_job.id, queue_name: sq_job.queue_name, priority: sq_job.priority,
              arguments: sq_job.arguments, terminated_at: Time.current)
    rescue StandardError => e
      SolidTerminator.configuration.logger.error(
        "Failed to record termination for job #{active_job.job_id}: #{e.class}: #{e.message}"
      )
      nil
    end

    def retry
      # Rows terminated before 0.2.0 whose job was already cleared got no arguments from the backfill.
      if arguments.nil?
        raise NotRetryable, "Cannot retry terminated execution #{id} (job #{job_id}): its arguments were not " \
                            'recorded. It was terminated before solid_terminator 0.2.0 and its job is gone.'
      end

      active_job = ActiveJob::Base.deserialize(arguments)
      transaction do
        destroy!
        active_job.enqueue
      end
    end
  end
end
