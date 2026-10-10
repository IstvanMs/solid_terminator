# frozen_string_literal: true

module SolidTerminator
  module Terminable
    extend ActiveSupport::Concern

    included do
      around_perform :with_termination_handling
      # rescue_from rather than rescuing in around_perform: perform_now then returns normally, so
      # SolidQueue marks the job finished, and after_perform callbacks from parent classes do not run.
      rescue_from(JobTerminated) { |error| handle_job_terminated(error) }
    end

    private

    def with_termination_handling
      current_thread = Thread.current
      st_logger.debug("Job #{job_id} registered for termination monitoring")
      ThreadRegistry.register(job_id)
      yield
    ensure
      ThreadRegistry.deregister(job_id, current_thread)
      st_logger.debug("Job #{job_id} deregistered from termination monitoring")
      cleanup_termination_row
    end

    def handle_job_terminated(error)
      st_logger.info("Job #{job_id} terminated: #{error.message}")
      SolidQueue::TerminatedExecution.record_termination(self)
    end

    def cleanup_termination_row
      Termination.where(active_job_id: job_id).delete_all
    rescue StandardError => e
      st_logger.error("Failed to delete termination row for job #{job_id}: #{e.class}: #{e.message}")
    end

    def st_logger
      SolidTerminator.configuration.logger
    end
  end
end
