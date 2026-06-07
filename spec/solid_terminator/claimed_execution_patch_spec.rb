# frozen_string_literal: true

require 'spec_helper'
require 'solid_terminator/claimed_execution_patch'

RSpec.describe SolidTerminator::ClaimedExecutionPatch do
  let(:fake_job) { instance_double(SolidQueue::Job, finished!: nil) }

  let(:result_class) do
    Struct.new(:success, :error) do
      def success? = success
    end
  end

  let(:execution_class) do
    job_double = fake_job
    result_klass = result_class
    Class.new do
      prepend SolidTerminator::ClaimedExecutionPatch

      attr_accessor :execute_result, :finished_called, :failed_with_error, :unblocked

      define_method(:job) { job_double }
      define_method(:result_class) { result_klass }

      def execute = execute_result
      def unblock_next_job = (@unblocked = true)
      def destroy! = nil
      def transaction = yield

      private

      def finished = (@finished_called = true)
      def failed_with(error) = (@failed_with_error = error)
    end
  end

  let(:execution) { execution_class.new }

  def success_result    = result_class.new(true, nil)
  def terminated_result = result_class.new(false, SolidTerminator::JobTerminated.new('terminated'))
  def error_result(err = RuntimeError.new('boom')) = result_class.new(false, err)

  describe '#perform' do
    context 'when execute succeeds' do
      before { execution.execute_result = success_result }

      it 'calls finished' do
        execution.perform
        expect(execution.finished_called).to be(true)
      end

      it 'always unblocks next job' do
        execution.perform
        expect(execution.unblocked).to be(true)
      end
    end

    context 'when execute returns a JobTerminated error' do
      before { execution.execute_result = terminated_result }

      it 'calls job.finished! inside a transaction' do
        execution.perform
        expect(fake_job).to have_received(:finished!)
      end

      it 'destroys the execution' do
        allow(execution).to receive(:destroy!)
        execution.perform
        expect(execution).to have_received(:destroy!)
      end

      it 'does not call failed_with' do
        execution.perform
        expect(execution.failed_with_error).to be_nil
      end

      it 'always unblocks next job' do
        execution.perform
        expect(execution.unblocked).to be(true)
      end
    end

    context 'when execute returns a regular error' do
      let(:error) { RuntimeError.new('boom') }

      before { execution.execute_result = error_result(error) }

      it 'calls failed_with' do
        execution.perform rescue nil # rubocop:disable Style/RescueModifier
        expect(execution.failed_with_error).to eq(error)
      end

      it 're-raises the error' do
        expect { execution.perform }.to raise_error(RuntimeError, 'boom')
      end

      it 'always unblocks next job' do
        execution.perform rescue nil # rubocop:disable Style/RescueModifier
        expect(execution.unblocked).to be(true)
      end
    end
  end
end
