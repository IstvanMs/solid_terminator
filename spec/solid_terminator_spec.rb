# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SolidTerminator do
  after do
    described_class.stop_monitor
  end

  describe '.terminate!' do
    it 'creates a termination row' do
      described_class.terminate!('job-abc')
      expect(SolidTerminator::Termination.exists?(active_job_id: 'job-abc')).to be(true)
    end

    it 'does not raise when called twice for the same job' do
      described_class.terminate!('job-abc')
      expect { described_class.terminate!('job-abc') }.not_to raise_error
    end

    it 'does not create a duplicate row when called twice' do
      described_class.terminate!('job-abc')
      described_class.terminate!('job-abc')
      expect(SolidTerminator::Termination.where(active_job_id: 'job-abc').count).to eq(1)
    end
  end

  describe '.start_monitor' do
    it 'starts the monitor' do
      described_class.start_monitor
      expect(described_class.instance_variable_get(:@monitor)).not_to be_nil
    end

    it 'is idempotent — calling twice spawns only one monitor thread' do
      described_class.start_monitor
      first_monitor = described_class.instance_variable_get(:@monitor)
      described_class.start_monitor
      expect(described_class.instance_variable_get(:@monitor)).to be(first_monitor)
    end
  end

  describe '.stop_monitor' do
    it 'stops and clears the monitor' do
      described_class.start_monitor
      described_class.stop_monitor
      expect(described_class.instance_variable_get(:@monitor)).to be_nil
    end

    it 'is safe to call when no monitor is running' do
      expect { described_class.stop_monitor }.not_to raise_error
    end
  end
end
