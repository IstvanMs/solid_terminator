# frozen_string_literal: true

require_relative '../integration_helper'

module IntegrationJobs
  class OkJob < ActiveJob::Base
    def perform; end
  end

  class FailingJob < ActiveJob::Base
    def perform
      raise ArgumentError, 'boom'
    end
  end

  class LongJob < ActiveJob::Base
    include SolidTerminator::Terminable

    limits_concurrency to: 1, key: 'integration_long_job'

    def perform
      loop { sleep 0.01 }
    end
  end
end

RSpec.describe SolidQueue::ClaimedExecution do
  def claim(active_job)
    job = SolidQueue::Job.find_by!(active_job_id: active_job.job_id)
    SolidQueue::ReadyExecution.claim(job.queue_name, 1, nil).first
  end

  def outcome_of
    yield
    nil
  rescue StandardError, SolidTerminator::JobTerminated => e
    e
  end

  context 'when the job succeeds' do
    let(:active_job) { IntegrationJobs::OkJob.perform_later }
    let!(:error) { outcome_of { claim(active_job).perform } }

    it 'does not raise' do
      expect(error).to be_nil
    end

    it 'marks the job finished' do
      expect(SolidQueue::Job.find_by!(active_job_id: active_job.job_id)).to be_finished
    end
  end

  context 'when the job fails' do
    let(:active_job) { IntegrationJobs::FailingJob.perform_later }
    let!(:error) { outcome_of { claim(active_job).perform } }

    it 'raises the job error, not a patch error' do
      expect(error).to be_a(ArgumentError)
    end

    it 'records a failed execution' do
      expect(SolidQueue::Job.find_by!(active_job_id: active_job.job_id)).to be_failed
    end
  end

  context 'when the job is terminated through terminate!' do
    let(:active_job) { IntegrationJobs::LongJob.perform_later }
    let(:blocked_job) { IntegrationJobs::LongJob.perform_later }
    let(:sq_job) { SolidQueue::Job.find_by!(active_job_id: active_job.job_id) }

    let!(:error) do
      claimed = claim(active_job)
      blocked_job
      monitor = SolidTerminator::Monitor.new(interval: 0.05)
      monitor.start
      worker = Thread.new { outcome_of { claimed.perform } }
      sleep 0.01 until SolidTerminator::ThreadRegistry.active_job_ids.include?(active_job.job_id)
      SolidTerminator.terminate!(active_job.job_id)
      worker.join(5) ? worker.value : raise('job was not terminated within 5s')
    ensure
      monitor&.stop
    end

    it 'does not raise' do
      expect(error).to be_nil
    end

    it 'marks the job finished' do
      expect(sq_job).to be_finished
    end

    it 'removes the claimed execution' do
      expect(described_class.exists?(job_id: sq_job.id)).to be(false)
    end

    it 'records a terminated execution' do
      expect(SolidQueue::TerminatedExecution.exists?(job_id: sq_job.id)).to be(true)
    end

    it 'deletes the termination request' do
      expect(SolidTerminator::Termination.exists?(active_job_id: active_job.job_id)).to be(false)
    end

    it 'unblocks the next job under the same concurrency limit' do
      blocked = SolidQueue::Job.find_by!(active_job_id: blocked_job.job_id)
      expect(SolidQueue::ReadyExecution.exists?(job_id: blocked.id)).to be(true)
    end
  end
end
