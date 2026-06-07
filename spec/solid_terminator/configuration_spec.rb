# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SolidTerminator::Configuration do
  subject(:config) { described_class.new }

  describe '#log_level' do
    it 'defaults to Logger::INFO' do
      expect(config.log_level).to eq(Logger::INFO)
    end
  end

  describe '#log_level=' do
    it 'updates the level before logger is built' do
      config.log_level = Logger::DEBUG
      expect(config.logger.level).to eq(Logger::DEBUG)
    end

    it 'updates the level on an already-built logger' do
      config.logger
      config.log_level = Logger::WARN
      expect(config.logger.level).to eq(Logger::WARN)
    end

    it 'accepts Logger::ERROR' do
      config.log_level = Logger::ERROR
      expect(config.log_level).to eq(Logger::ERROR)
    end
  end

  describe '#logger=' do
    it 'overrides the auto-built logger' do
      custom = Logger.new(nil)
      config.logger = custom
      expect(config.logger).to be(custom)
    end

    it 'persists across repeated calls' do
      custom = Logger.new(nil)
      config.logger = custom
      config.logger
      expect(config.logger).to be(custom)
    end

    it 'does not mutate the external logger when log_level is changed' do
      custom = Logger.new(nil)
      custom.level = Logger::INFO
      config.logger = custom
      config.log_level = Logger::DEBUG
      expect(custom.level).to eq(Logger::INFO)
    end
  end

  describe '#logger' do
    it 'applies log_level when building the logger' do
      config.log_level = Logger::DEBUG
      expect(config.logger.level).to eq(Logger::DEBUG)
    end

    it 'returns the same instance on repeated calls' do
      first = config.logger
      expect(config.logger).to be(first)
    end

    it 'rebuilds logger after log_file change' do
      original = config.logger
      config.log_file = $stdout
      expect(config.logger).not_to be(original)
    end
  end
end
