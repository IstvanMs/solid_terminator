SolidTerminator.configure do |config|
  # How often the monitor thread polls for termination requests (seconds).
  # config.polling_interval = 5

  # Use Rails.logger (or any Logger-compatible object) instead of a dedicated file.
  # config.logger = Rails.logger

  # Log file path. Defaults to log/solid_terminator.log. Ignored when config.logger is set.
  # config.log_file = Rails.root.join("log", "solid_terminator.log")

  # Log level. Defaults to Logger::INFO.
  # Use Logger::DEBUG for verbose output, Logger::WARN to suppress routine messages.
  # config.log_level = Logger::INFO
end
