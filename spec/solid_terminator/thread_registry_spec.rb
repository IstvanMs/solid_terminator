# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SolidTerminator::ThreadRegistry do
  let(:job_id) { 'abc-123' }
  let(:thread) { Thread.current }

  describe '.register / .thread_for' do
    it 'maps job id to thread' do
      described_class.register(job_id, thread)
      expect(described_class.thread_for(job_id)).to eq(thread)
    end
  end

  describe '.deregister' do
    it 'removes the mapping when no thread given' do
      described_class.register(job_id, thread)
      described_class.deregister(job_id)
      expect(described_class.thread_for(job_id)).to be_nil
    end

    it 'removes the mapping when the owning thread matches' do
      described_class.register(job_id, thread)
      described_class.deregister(job_id, thread)
      expect(described_class.thread_for(job_id)).to be_nil
    end

    it 'does not remove when a different thread is given' do
      other_thread = Thread.new { sleep }.tap { |t| t.abort_on_exception = false }
      described_class.register(job_id, thread)
      described_class.deregister(job_id, other_thread)
      expect(described_class.thread_for(job_id)).to eq(thread)
    ensure
      other_thread.kill
    end
  end

  describe '.empty?' do
    it 'true when no jobs registered' do
      expect(described_class.empty?).to be(true)
    end

    it 'false when job registered' do
      described_class.register(job_id, thread)
      expect(described_class.empty?).to be(false)
    end
  end

  describe '.active_job_ids' do
    it 'returns all registered ids' do
      described_class.register('id-1', thread)
      described_class.register('id-2', thread)
      expect(described_class.active_job_ids).to contain_exactly('id-1', 'id-2')
    end
  end

  describe '.snapshot' do
    it 'returns nil when registry is empty' do
      expect(described_class.snapshot).to be_nil
    end

    it 'returns all registered job ids when non-empty' do
      described_class.register('id-1', thread)
      described_class.register('id-2', thread)
      expect(described_class.snapshot).to contain_exactly('id-1', 'id-2')
    end
  end

  describe '.raise_in' do
    context 'when the job is registered on a live thread' do
      let(:ready) { Queue.new }
      let(:target) do
        started = ready
        Thread.new do
          started.push(:ready)
          sleep(10)
        rescue SolidTerminator::JobTerminated => e
          e
        end
      end

      before do
        described_class.register(job_id, target)
        ready.pop
      end

      after do
        target.kill
        described_class.deregister(job_id)
      end

      it 'returns :raised' do
        expect(described_class.raise_in(job_id, SolidTerminator::JobTerminated, 'stop')).to eq(:raised)
      end

      it 'raises the exception on that thread' do
        described_class.raise_in(job_id, SolidTerminator::JobTerminated, 'stop')
        expect(target.join(2)&.value).to be_a(SolidTerminator::JobTerminated)
      end
    end

    context 'when the job is not registered' do
      it 'returns :not_registered' do
        expect(described_class.raise_in(job_id, SolidTerminator::JobTerminated, 'stop')).to eq(:not_registered)
      end
    end

    context 'when the registered thread is dead' do
      before { described_class.register(job_id, Thread.new { nil }.tap(&:join)) }

      it 'returns :dead' do
        expect(described_class.raise_in(job_id, SolidTerminator::JobTerminated, 'stop')).to eq(:dead)
      end
    end
  end

  describe '.purge_dead_threads' do
    let(:live) { Thread.new { sleep(10) } }
    let(:dead) { Thread.new { nil }.tap(&:join) }

    before do
      described_class.register('live', live)
      described_class.register('dead', dead)
      described_class.purge_dead_threads
    end

    after do
      live.kill
      described_class.deregister('live')
    end

    it 'removes dead threads' do
      expect(described_class.thread_for('dead')).to be_nil
    end

    it 'keeps live threads' do
      expect(described_class.thread_for('live')).to eq(live)
    end
  end

  describe 'thread safety' do
    it 'handles concurrent register/deregister without corruption' do
      threads = 20.times.map do |i|
        Thread.new do
          id = "job-#{i}"
          described_class.register(id, Thread.current)
          sleep(rand * 0.01)
          described_class.deregister(id)
        end
      end
      threads.each(&:join)
      expect(described_class.empty?).to be(true)
    end
  end
end
