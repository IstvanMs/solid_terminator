# frozen_string_literal: true

require 'rails'

module SolidTerminator
  class Engine < Rails::Engine
    config.to_prepare do
      require 'solid_terminator/termination'
      require 'solid_terminator/terminated_execution'
    end

    config.after_initialize do
      if defined?(SolidQueue)
        SolidQueue.on_worker_start { SolidTerminator.start_monitor }
        SolidQueue.on_worker_stop  { SolidTerminator.stop_monitor }
      end
    end
  end
end
