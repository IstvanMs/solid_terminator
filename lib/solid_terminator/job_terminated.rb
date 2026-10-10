# frozen_string_literal: true

module SolidTerminator
  # Inherits Exception, not StandardError, so a job's bare `rescue => e` cannot swallow termination.
  class JobTerminated < Exception; end # rubocop:disable Lint/InheritException
end
