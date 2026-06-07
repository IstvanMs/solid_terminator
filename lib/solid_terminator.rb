# frozen_string_literal: true

require 'active_record'
require 'active_job'
require 'active_support'

require 'solid_terminator/version'
require 'solid_terminator/job_terminated'
require 'solid_terminator/configuration'
require 'solid_terminator/thread_registry'
require 'solid_terminator/terminable'
require 'solid_terminator/monitor'
require 'solid_terminator/engine' if defined?(Rails::Engine)

module SolidTerminator
  @monitor_mutex = Mutex.new

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end

    def terminate!(active_job_id)
      configuration.logger.info("Termination requested for job #{active_job_id}")
      Termination.create!(active_job_id: active_job_id)
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      raise if e.is_a?(ActiveRecord::RecordInvalid) && !e.record.errors.of_kind?(:active_job_id, :taken)

      configuration.logger.warn("Termination already requested for job #{active_job_id}")
    end

    def start_monitor
      @monitor_mutex.synchronize do
        return if @monitor

        @monitor = Monitor.new
        @monitor.start
      end
    end

    def stop_monitor
      @monitor_mutex.synchronize do
        @monitor&.stop
        @monitor = nil
      end
    end
  end
end
