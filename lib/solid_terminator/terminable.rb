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

    # JobTerminated is only delivered while the job's own code runs. During registration and cleanup
    # it is deferred, so a signal cannot interrupt deregister and leave a stale entry that would make
    # the monitor raise into the next job on this pool thread.
    def with_termination_handling(&)
      current_thread = Thread.current
      Thread.handle_interrupt(JobTerminated => :never) do
        ThreadRegistry.register(job_id)
        st_logger.debug("Job #{job_id} registered for termination monitoring")
        Thread.handle_interrupt(JobTerminated => :immediate, &)
      ensure
        finish_termination_handling(current_thread)
      end
    end

    def finish_termination_handling(current_thread)
      ThreadRegistry.deregister(job_id, current_thread)
      st_logger.debug("Job #{job_id} deregistered from termination monitoring")
      cleanup_termination_row
      discard_pending_termination
    end

    # A signal sent just before deregister is still queued. The job is over either way, so drop it
    # instead of letting it fire after the mask lifts and mark a completed job as terminated.
    # Unmasking delivers any queued signal; no Thread.pending_interrupt?(JobTerminated) guard
    # because that call segfaults on Ruby 3.1 while the interrupt is pending.
    def discard_pending_termination
      Thread.handle_interrupt(JobTerminated => :immediate) { nil }
    rescue JobTerminated
      nil
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
