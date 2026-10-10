# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SolidTerminator::Monitor do
  let(:interval) { 0.05 }
  let(:monitor)  { described_class.new(interval: interval) }

  after { monitor.stop }

  describe 'skip when registry empty' do
    it 'does not query DB when no jobs running' do
      allow(SolidTerminator::Termination).to receive(:for_jobs)
      monitor.start
      sleep(interval * 2)
      expect(SolidTerminator::Termination).not_to have_received(:for_jobs)
    end
  end

  describe 'raises on target thread when termination found' do
    it 'raises JobTerminated on the registered thread' do
      job_id  = 'job-to-terminate'
      barrier = Queue.new
      raised  = nil

      target = Thread.new do
        SolidTerminator::ThreadRegistry.register(job_id)
        barrier.push(:ready)
        sleep(10)
      rescue SolidTerminator::JobTerminated => e
        raised = e
      end

      barrier.pop
      SolidTerminator::Termination.create!(active_job_id: job_id)
      monitor.start
      target.join(2)

      expect(raised).to be_a(SolidTerminator::JobTerminated)
    end

    it 'deletes termination row after raising' do
      job_id  = 'job-cleanup'
      barrier = Queue.new

      target = Thread.new do
        SolidTerminator::ThreadRegistry.register(job_id)
        barrier.push(:ready)
        sleep(10)
      rescue SolidTerminator::JobTerminated
        nil
      end

      barrier.pop
      SolidTerminator::Termination.create!(active_job_id: job_id)
      monitor.start
      target.join(2)
      sleep(interval * 3) # wait for clean_stale_entry on the next poll

      expect(SolidTerminator::Termination.exists?(active_job_id: job_id)).to be(false)
    end
  end

  describe 'does not delete termination rows for jobs on other workers' do
    it 'preserves termination rows not in local registry' do
      other_job_id = 'job-on-other-worker'
      local_job_id = 'local-job'
      barrier      = Queue.new

      SolidTerminator::Termination.create!(active_job_id: other_job_id)

      local_thread = Thread.new do
        SolidTerminator::ThreadRegistry.register(local_job_id)
        barrier.push(:ready)
        sleep(10)
      rescue SolidTerminator::JobTerminated
        nil
      end

      barrier.pop
      monitor.start
      sleep(interval * 3)
      local_thread.kill
      local_thread.join
      SolidTerminator::ThreadRegistry.deregister(local_job_id)

      expect(SolidTerminator::Termination.exists?(active_job_id: other_job_id)).to be(true)
    end
  end

  describe 'cleans up stale registry entries for dead threads' do
    let(:job_id) { 'dead-job' }
    let(:dead)   { Thread.new { nil }.tap(&:join) }

    before do
      SolidTerminator::ThreadRegistry.register(job_id, dead)
      SolidTerminator::Termination.create!(active_job_id: job_id)
      monitor.start
      sleep(interval * 3)
    end

    it 'does not raise' do
      # passes as long as monitor is still running (no unhandled exception)
      expect(monitor).to be_a(described_class)
    end

    it 'destroys the termination row' do
      expect(SolidTerminator::Termination.exists?(active_job_id: job_id)).to be(false)
    end

    it 'deregisters the dead thread' do
      expect(SolidTerminator::ThreadRegistry.thread_for(job_id)).to be_nil
    end
  end

  describe 'cleans up termination row when thread dies between alive? and raise' do
    it 'destroys the termination row on the next poll via clean_stale_entry' do
      job_id = 'dying-job'
      thread = Thread.new { sleep(10) }
      SolidTerminator::ThreadRegistry.register(job_id, thread)
      SolidTerminator::Termination.create!(active_job_id: job_id)

      thread.kill
      thread.join

      monitor.start
      sleep(interval * 3)

      expect(SolidTerminator::Termination.exists?(active_job_id: job_id)).to be(false)
    end
  end

  describe 'retries termination if job swallows the exception and continues running' do
    let(:job_id) { 'stubborn-job' }

    # Swallows the first JobTerminated, lets the second one end the thread; the value is the raise count.
    let(:stubborn_job) do
      # Read the let before spawning: RSpec holds the memoization lock until this block returns.
      id      = job_id
      barrier = Queue.new
      thread = Thread.new do
        raise_count = 0
        SolidTerminator::ThreadRegistry.register(id)
        barrier.push(:ready)
        loop do
          sleep(1)
        rescue SolidTerminator::JobTerminated
          raise_count += 1
          raise if raise_count >= 2
        end
      rescue SolidTerminator::JobTerminated
        raise_count
      end
      barrier.pop
      thread
    end

    it 'raises again on the next poll until the job stops' do
      stubborn_job
      SolidTerminator::Termination.create!(active_job_id: job_id)
      monitor.start

      expect(stubborn_job.join(2)&.value).to be >= 2
    ensure
      stubborn_job.kill
      SolidTerminator::ThreadRegistry.deregister(job_id)
    end
  end

  describe 'does not remove a re-registered thread when old job deregisters' do
    it 'preserves the new thread after deregister with wrong thread' do
      job_id     = 'shared-job-id'
      new_thread = Thread.new { sleep(10) }

      SolidTerminator::ThreadRegistry.register(job_id, Thread.current)
      SolidTerminator::ThreadRegistry.register(job_id, new_thread)
      SolidTerminator::ThreadRegistry.deregister(job_id, Thread.current)

      expect(SolidTerminator::ThreadRegistry.thread_for(job_id)).to eq(new_thread)
    ensure
      new_thread.kill
      SolidTerminator::ThreadRegistry.deregister(job_id)
    end
  end
end
