# frozen_string_literal: true

# Boots a minimal Rails app on the real solid_queue models, so termination runs through
# whatever solid_queue version is bundled. Kept apart from spec/ because spec_helper
# defines fake SolidQueue models that clash with the real ones.

require 'erb'
require 'tmpdir'
require 'rails'
require 'active_record/railtie'
require 'active_job/railtie'
require 'solid_queue'
require 'solid_terminator'

DB_PATH = File.join(Dir.tmpdir, "solid_terminator_integration_#{Process.pid}.db")
# File DB rather than :memory: so the monitor thread's connection sees the same data.
ENV['DATABASE_URL'] = "sqlite3:#{DB_PATH}?timeout=5000"

class IntegrationApp < Rails::Application
  config.eager_load = false
  config.logger = Logger.new(nil)
  config.active_job.queue_adapter = :solid_queue
  config.secret_key_base = 'integration'
end

IntegrationApp.initialize!

ActiveRecord::Migration.verbose = false
load File.join(Gem.loaded_specs['solid_queue'].full_gem_path,
               'lib/generators/solid_queue/install/templates/db/queue_schema.rb')

%w[
  create_solid_queue_terminations
  create_solid_queue_terminated_executions
  add_arguments_to_solid_queue_terminated_executions
].map { |name| File.expand_path("../lib/generators/solid_terminator/templates/#{name}.rb", __dir__) }.each do |template|
  rendered = File.join(Dir.tmpdir, "#{Process.pid}_#{File.basename(template)}")
  File.write(rendered, ERB.new(File.read(template)).result_with_hash(
                         migration_version: "[#{ActiveRecord::Migration.current_version}]"
                       ))
  load rendered
  File.basename(template, '.rb').camelize.constantize.migrate(:up)
ensure
  FileUtils.rm_f(rendered)
end

SolidTerminator.configuration.logger = Logger.new(nil)

at_exit { FileUtils.rm_f(DB_PATH) }

RSpec.configure do |config|
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.around do |example|
    example.run
  ensure
    connection = ActiveRecord::Base.connection
    connection.tables.grep(/\Asolid_queue_/).each { |table| connection.execute("DELETE FROM #{table}") }
  end
end
