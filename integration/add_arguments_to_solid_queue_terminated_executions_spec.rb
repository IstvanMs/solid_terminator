# frozen_string_literal: true

require_relative 'integration_helper'

RSpec.describe AddArgumentsToSolidQueueTerminatedExecutions do
  let(:kept_job)    { SolidQueue::Job.create!(queue_name: 'default', class_name: 'KeptJob', arguments: { 'job_class' => 'KeptJob' }) }
  let(:cleared_job) { SolidQueue::Job.create!(queue_name: 'default', class_name: 'ClearedJob', arguments: {}) }

  def terminated_for(job) = SolidQueue::TerminatedExecution.find_by!(job_id: job.id)

  around do |example|
    example.run
  ensure
    SolidQueue::TerminatedExecution.reset_column_information
  end

  # Simulates an install upgraded from 0.1: rows exist before the column does.
  before do
    [kept_job, cleared_job].each do |job|
      SolidQueue::TerminatedExecution.create!(job: job, queue_name: 'default', priority: 0, terminated_at: Time.current)
    end
    migration = described_class.new
    migration.migrate(:down)
    cleared_job.delete
    migration.migrate(:up)
    SolidQueue::TerminatedExecution.reset_column_information
  end

  it 'copies arguments from jobs SolidQueue has not cleared' do
    expect(terminated_for(kept_job).arguments).to eq('job_class' => 'KeptJob')
  end

  it 'leaves arguments empty when the job is already gone' do
    expect(terminated_for(cleared_job).arguments).to be_nil
  end
end
