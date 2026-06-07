# frozen_string_literal: true

require 'active_record'
require 'active_job'
require 'active_support'
require 'fileutils'

DB_PATH = "/tmp/solid_terminator_test_#{Process.pid}.db".freeze
ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: DB_PATH)

ActiveRecord::Schema.define do
  create_table :solid_queue_terminations, force: true do |t|
    t.string   :active_job_id, null: false
    t.datetime :created_at,    null: false
  end
  add_index :solid_queue_terminations, :active_job_id, unique: true

  create_table :solid_queue_jobs, force: true do |t|
    t.string   :active_job_id, null: false
    t.string   :class_name,    null: false
    t.string   :queue_name,    null: false
    t.integer  :priority,      default: 0, null: false
    t.text     :arguments,     default: '[]'
    t.datetime :created_at,    null: false
  end

  create_table :solid_queue_terminated_executions, force: true do |t|
    t.bigint   :job_id,        null: false
    t.integer  :priority,      default: 0, null: false
    t.string   :queue_name,    null: false
    t.datetime :terminated_at, null: false
    t.datetime :created_at,    null: false
  end
  add_index :solid_queue_terminated_executions, :job_id, unique: true
end

module SolidQueue
  class Record < ActiveRecord::Base
    self.abstract_class = true
    self.table_name_prefix = 'solid_queue_'
  end

  class Execution < Record
    self.abstract_class = true

    belongs_to :job, class_name: 'SolidQueue::Job'
  end

  class Job < Record
    serialize :arguments, coder: JSON

    def finished!
      destroy!
    end
  end
end

require 'solid_terminator'
require 'solid_terminator/termination'
require 'solid_terminator/terminated_execution'

ActiveJob::Base.logger = Logger.new(nil)
SolidTerminator.configuration.logger = Logger.new(nil)

at_exit { FileUtils.rm_f(DB_PATH) }

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  config.after do
    SolidTerminator::Termination.delete_all
    SolidQueue::TerminatedExecution.delete_all
    SolidQueue::Job.delete_all
    SolidTerminator::ThreadRegistry.active_job_ids.each do |id|
      SolidTerminator::ThreadRegistry.deregister(id)
    end
  end
end
