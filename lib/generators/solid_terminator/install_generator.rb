# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/active_record'

module SolidTerminator
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path('templates', __dir__)

      class_option :database,
                   type: :string,
                   aliases: '-d',
                   desc: 'Target database key from database.yml (default: auto-detected from queue DB config).'

      def self.next_migration_number(dirname)
        ActiveRecord::Generators::Base.next_migration_number(dirname)
      end

      def copy_migrations
        migration_template \
          'create_solid_queue_terminations.rb',
          File.join(target_migrations_dir, 'create_solid_queue_terminations.rb')

        migration_template \
          'create_solid_queue_terminated_executions.rb',
          File.join(target_migrations_dir, 'create_solid_queue_terminated_executions.rb')

        migration_template \
          'add_arguments_to_solid_queue_terminated_executions.rb',
          File.join(target_migrations_dir, 'add_arguments_to_solid_queue_terminated_executions.rb')
      end

      def create_initializer
        template 'initializer.rb', 'config/initializers/solid_terminator.rb'
      end

      private

      def target_migrations_dir
        db_key = options[:database] || 'queue'
        db_config = ActiveRecord::Base.configurations.find_db_config(db_key)
        Array(db_config&.migrations_paths).first || 'db/migrate'
      end

      def migration_version
        "[#{ActiveRecord::Migration.current_version}]"
      end
    end
  end
end
