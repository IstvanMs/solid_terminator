# frozen_string_literal: true

require 'spec_helper'

class TerminableTestJob < ActiveJob::Base
  include SolidTerminator::Terminable

  queue_as :default
  attr_writer :work
  attr_reader :after_performed

  after_perform { @after_performed = true }

  def perform
    @work&.call
  end
end

RSpec.describe SolidTerminator::Terminable do
  let(:job)    { TerminableTestJob.new }
  let(:job_id) { job.job_id }

  describe 'thread registry' do
    it 'deregisters after successful perform' do
      job.perform_now
      expect(SolidTerminator::ThreadRegistry.thread_for(job_id)).to be_nil
    end

    it 'propagates non-termination errors' do
      job.work = -> { raise 'boom' }
      expect { job.perform_now }.to raise_error(RuntimeError, 'boom')
    end

    it 'deregisters even when perform raises' do
      job.work = -> { raise 'boom' }
      job.perform_now rescue nil # rubocop:disable Style/RescueModifier
      expect(SolidTerminator::ThreadRegistry.thread_for(job_id)).to be_nil
    end
  end

  describe 'JobTerminated handling' do
    let!(:sq_job) do
      SolidQueue::Job.create!(
        active_job_id: job_id,
        class_name: 'TerminableTestJob',
        queue_name: 'default',
        priority: 0
      )
    end

    before { job.work = -> { raise SolidTerminator::JobTerminated } }

    it 'does not raise, so the queue marks the job finished' do
      expect { job.perform_now }.not_to raise_error
    end

    it 'does not run after_perform callbacks' do
      job.perform_now
      expect(job.after_performed).to be_nil
    end

    it 'deregisters after termination' do
      job.perform_now
      expect(SolidTerminator::ThreadRegistry.thread_for(job_id)).to be_nil
    end

    it 'creates a TerminatedExecution record' do
      job.perform_now
      expect(SolidQueue::TerminatedExecution.find_by(job_id: sq_job.id)).not_to be_nil
    end

    it 'stores the correct queue_name on the TerminatedExecution record' do
      job.perform_now
      record = SolidQueue::TerminatedExecution.find_by(job_id: sq_job.id)
      expect(record.queue_name).to eq('default')
    end
  end

  describe 'termination row cleanup' do
    it 'deletes termination row after normal completion' do
      SolidTerminator::Termination.create!(active_job_id: job_id)
      job.perform_now
      expect(SolidTerminator::Termination.exists?(active_job_id: job_id)).to be(false)
    end

    it 'deletes termination row after error' do
      SolidTerminator::Termination.create!(active_job_id: job_id)
      job.work = -> { raise 'boom' }
      job.perform_now rescue nil # rubocop:disable Style/RescueModifier
      expect(SolidTerminator::Termination.exists?(active_job_id: job_id)).to be(false)
    end

    it 'deletes termination row after termination' do
      SolidTerminator::Termination.create!(active_job_id: job_id)
      job.work = -> { raise SolidTerminator::JobTerminated }
      job.perform_now
      expect(SolidTerminator::Termination.exists?(active_job_id: job_id)).to be(false)
    end
  end
end
