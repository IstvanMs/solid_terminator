# frozen_string_literal: true

module SolidTerminator
  module ThreadRegistry
    @mutex    = Mutex.new
    @registry = {}

    class << self
      def register(active_job_id, thread = Thread.current)
        @mutex.synchronize { @registry[active_job_id] = thread }
      end

      def deregister(active_job_id, thread = nil)
        @mutex.synchronize do
          return if thread && !@registry[active_job_id].equal?(thread)

          @registry.delete(active_job_id)
        end
      end

      def thread_for(active_job_id)
        @mutex.synchronize { @registry[active_job_id] }
      end

      def active_job_ids
        @mutex.synchronize { @registry.keys.dup }
      end

      def snapshot
        @mutex.synchronize do
          return nil if @registry.empty?

          @registry.keys.dup
        end
      end

      def purge_dead_threads
        @mutex.synchronize { @registry.delete_if { |_, t| !t.alive? } }
      end

      def empty?
        @mutex.synchronize { @registry.empty? }
      end
    end
  end
end
