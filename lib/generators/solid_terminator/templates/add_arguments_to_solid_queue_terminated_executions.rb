class AddArgumentsToSolidQueueTerminatedExecutions < ActiveRecord::Migration<%= migration_version %>
  def up
    add_column :solid_queue_terminated_executions, :arguments, :text

    # Copy from jobs SolidQueue has not cleared yet; rows whose job is already gone stay NULL and cannot be retried.
    execute <<~SQL
      UPDATE solid_queue_terminated_executions
      SET arguments = (
        SELECT solid_queue_jobs.arguments FROM solid_queue_jobs
        WHERE solid_queue_jobs.id = solid_queue_terminated_executions.job_id
      )
    SQL
  end

  def down
    remove_column :solid_queue_terminated_executions, :arguments
  end
end
