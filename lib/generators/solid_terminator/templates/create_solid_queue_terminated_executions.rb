class CreateSolidQueueTerminatedExecutions < ActiveRecord::Migration<%= migration_version %>
  def change
    create_table :solid_queue_terminated_executions do |t|
      t.bigint   :job_id,        null: false
      t.integer  :priority,      default: 0, null: false
      t.string   :queue_name,    null: false
      t.datetime :terminated_at, null: false
      t.datetime :created_at,    null: false
    end

    add_index :solid_queue_terminated_executions, :job_id, unique: true
    add_index :solid_queue_terminated_executions, %i[queue_name priority job_id],
              name: 'index_solid_queue_terminated_executions_for_filtering'
  end
end
