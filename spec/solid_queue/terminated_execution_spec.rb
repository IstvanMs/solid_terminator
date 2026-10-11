# frozen_string_literal: true

require 'spec_helper'

class RetryableJob < ActiveJob::Base
  def perform(*); end
end

RSpec.describe SolidQueue::TerminatedExecution do
  let(:active_job_id) { 'test-job-abc-123' }
  let(:sq_job) do
    SolidQueue::Job.create!(
      active_job_id: active_job_id,
      class_name: 'FakeJob',
      queue_name: 'critical',
      priority: 5,
      arguments: { 'job_class' => 'FakeJob', 'arguments' => [1] }
    )
  end

  let(:fake_active_job) do
    instance_double(ActiveJob::Base, job_id: active_job_id)
  end

  describe '.record_termination' do
    subject(:record) { described_class.record_termination(fake_active_job) }

    before { sq_job }

    it 'persists a new record' do
      expect(record).to be_persisted
    end

    it 'stores the job_id' do
      expect(record.job_id).to eq(sq_job.id)
    end

    it 'stores the queue_name' do
      expect(record.queue_name).to eq('critical')
    end

    it 'stores the priority' do
      expect(record.priority).to eq(5)
    end

    it 'stores the job arguments' do
      expect(record.arguments).to eq('job_class' => 'FakeJob', 'arguments' => [1])
    end

    it 'records terminated_at' do
      expect(record.terminated_at).to be_within(2).of(Time.current)
    end

    it 'returns nil when SolidQueue job not found' do
      allow(SolidQueue::Job).to receive(:find_by).and_return(nil)
      expect(described_class.record_termination(fake_active_job)).to be_nil
    end

    it 'does not raise when creation fails' do
      allow(described_class).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
      expect { described_class.record_termination(fake_active_job) }.not_to raise_error
    end

    it 'returns nil when creation fails' do
      allow(described_class).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)
      expect(described_class.record_termination(fake_active_job)).to be_nil
    end
  end

  describe '#retry' do
    let(:terminated) do
      aj = RetryableJob.new
      sq = SolidQueue::Job.create!(
        active_job_id: aj.job_id,
        class_name: 'RetryableJob',
        queue_name: 'critical',
        priority: 5,
        arguments: aj.serialize
      )
      described_class.record_termination(instance_double(ActiveJob::Base, job_id: aj.job_id))
      described_class.find_by!(job_id: sq.id)
    end

    around do |example|
      original = ActiveJob::Base.queue_adapter
      ActiveJob::Base.queue_adapter = :test
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      example.run
    ensure
      ActiveJob::Base.queue_adapter = original
    end

    it 'destroys the terminated execution record' do
      id = terminated.job_id
      terminated.retry
      expect(described_class.find_by(job_id: id)).to be_nil
    end

    it 'enqueues a new job' do
      expect { terminated.retry }
        .to change { ActiveJob::Base.queue_adapter.enqueued_jobs.size }.by(1)
    end

    context 'when SolidQueue has already cleared the finished job' do
      before { SolidQueue::Job.where(id: terminated.job_id).delete_all }

      it 'still enqueues a new job' do
        expect { terminated.retry }
          .to change { ActiveJob::Base.queue_adapter.enqueued_jobs.size }.by(1)
      end
    end

    context 'when the arguments were never recorded' do
      before { terminated.update_column(:arguments, nil) }

      def attempt_retry
        terminated.retry
      rescue described_class::NotRetryable
        nil
      end

      it 'raises NotRetryable' do
        expect { terminated.retry }.to raise_error(described_class::NotRetryable, /arguments were not recorded/)
      end

      it 'keeps the terminated execution record' do
        expect { attempt_retry }.not_to change(described_class, :count)
      end

      it 'does not enqueue a job' do
        expect { attempt_retry }.not_to(change { ActiveJob::Base.queue_adapter.enqueued_jobs.size })
      end
    end
  end
end
