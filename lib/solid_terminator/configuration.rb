# frozen_string_literal: true

require 'logger'

module SolidTerminator
  class Configuration
    attr_accessor :polling_interval
    attr_reader :log_file, :log_level

    def initialize
      @polling_interval = 5
      @log_level = Logger::INFO
    end

    def log_file=(path)
      @log_file = path
      @logger = nil
    end

    def log_level=(level)
      @log_level = level
      @logger.level = level if @logger && !@external_logger
    end

    def logger=(logger)
      @logger = logger
      @external_logger = true
    end

    def logger
      @logger ||= Logger.new(log_file || default_log_path).tap do |l|
        l.progname = 'SolidTerminator'
        l.level    = @log_level
      end
    end

    private

    def default_log_path
      defined?(Rails) && Rails.root ? Rails.root.join('log', 'solid_terminator.log') : $stdout
    end
  end
end
