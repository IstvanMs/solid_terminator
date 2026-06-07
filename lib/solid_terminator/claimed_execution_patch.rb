# frozen_string_literal: true

module SolidTerminator
  module ClaimedExecutionPatch
    def perform
      result = execute
      handle_result(result)
    ensure
      unblock_next_job
    end

    private

    def handle_result(result)
      if result.success?
        finished
      elsif result.error.is_a?(SolidTerminator::JobTerminated)
        finish_terminated
      else
        failed_with(result.error)
        raise result.error
      end
    end

    def finish_terminated
      transaction do
        job.finished!
        destroy!
      end
    end
  end
end
