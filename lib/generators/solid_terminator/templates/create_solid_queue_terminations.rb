class CreateSolidQueueTerminations < ActiveRecord::Migration<%= migration_version %>
  def change
    create_table :solid_queue_terminations do |t|
      t.string   :active_job_id, null: false
      t.datetime :created_at,    null: false
    end

    add_index :solid_queue_terminations, :active_job_id, unique: true
  end
end
