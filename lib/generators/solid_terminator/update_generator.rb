# frozen_string_literal: true

require_relative 'install_generator'

module SolidTerminator
  module Generators
    class UpdateGenerator < InstallGenerator
      source_root File.expand_path('templates', __dir__)

      remove_command :create_initializer

      private

      def migration_template(source, destination, config = {})
        super(source, destination, config.merge(skip: true))
      end
    end
  end
end
