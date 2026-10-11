# frozen_string_literal: true

require_relative '../../integration_helper'
require 'generators/solid_terminator/install_generator'

RSpec.describe SolidTerminator::Generators::InstallGenerator do
  let(:destination) { Dir.mktmpdir }
  let(:all_migrations) do
    %w[
      create_solid_queue_terminations.rb
      create_solid_queue_terminated_executions.rb
      add_arguments_to_solid_queue_terminated_executions.rb
    ]
  end

  around do |example|
    example.run
  ensure
    FileUtils.rm_rf(destination)
  end

  def run_generator(*args)
    described_class.start([*args, '--quiet'], destination_root: destination)
  end

  def migrations
    Dir[File.join(destination, 'db/migrate/*.rb')].map { |path| File.basename(path).sub(/\A\d+_/, '') }
  end

  it 'creates every migration on a fresh install' do
    run_generator
    expect(migrations).to match_array(all_migrations)
  end

  context 'when upgrading an install made before the arguments column existed' do
    before do
      run_generator
      FileUtils.rm(Dir[File.join(destination, 'db/migrate/*_add_arguments_*.rb')])
      # Older installs were generated under another Rails version, so their files are not identical.
      Dir[File.join(destination, 'db/migrate/*.rb')].each do |path|
        File.write(path, File.read(path).sub(/Migration\[[\d.]+\]/, 'Migration[7.0]'))
      end
      run_generator('--skip')
    end

    it 'adds only the missing migration' do
      expect(migrations).to match_array(all_migrations)
    end
  end
end
