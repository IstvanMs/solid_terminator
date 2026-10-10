# frozen_string_literal: true

module SolidTerminator
  class Monitor
    def initialize(interval: SolidTerminator.configuration.polling_interval)
      @interval = interval
      @mutex    = Mutex.new
      @stopped  = false
    end

    def start
      logger.info("Monitor starting (polling every #{@interval}s)")
      @thread = Thread.new { run }
      @thread.name = 'SolidTerminator::Monitor'
      @thread
    end

    def stop
      logger.info('Monitor stopping')
      @mutex.synchronize { @stopped = true }
      begin
        @thread&.wakeup
      rescue ThreadError
        nil
      end
      @thread&.join(@interval + 2)
    end

    private

    def stopped?
      @mutex.synchronize { @stopped }
    end

    def run
      retries = 0
      until stopped?
        check_for_terminations
        sleep @interval
      end
    rescue ActiveRecord::StatementInvalid => e
      logger.error("Monitor stopped — table missing, run migrations. #{e.message}")
    rescue StandardError => e
      retries = on_run_error(e, retries)
      retry unless stopped?
    end

    def on_run_error(error, retries)
      retries += 1
      logger.error("Monitor error (attempt #{retries}): #{error.class}: #{error.message}. Retrying in #{@interval}s.")
      sleep @interval
      retries
    end

    def check_for_terminations
      job_ids = ThreadRegistry.snapshot
      if job_ids.nil?
        logger.debug('Skipping — no jobs registered')
      else
        process_terminations(job_ids)
        ThreadRegistry.purge_dead_threads
      end
    end

    def process_terminations(job_ids)
      return if job_ids.empty?

      logger.debug("Checking for terminations (#{job_ids.size} job(s) registered)")
      Termination.for_jobs(job_ids).each { |t| signal_termination(t) }
    end

    def signal_termination(termination)
      job_id = termination.active_job_id
      case ThreadRegistry.raise_in(job_id, JobTerminated, "Job #{job_id} terminated")
      when :raised then logger.info("Raised termination on job #{job_id}")
      when :dead   then clean_stale_entry(termination)
      end
      # Row stays: job's ensure deletes it on clean exit; if the job swallows the exception
      # the row persists so the monitor retries next poll rather than silently giving up.
    end

    def clean_stale_entry(termination)
      logger.warn("Thread for job #{termination.active_job_id} is dead; cleaning up stale entry")
      ThreadRegistry.deregister(termination.active_job_id)
      termination.destroy
    end

    def logger
      SolidTerminator.configuration.logger
    end
  end
end
