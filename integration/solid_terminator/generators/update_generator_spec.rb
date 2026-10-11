# frozen_string_literal: true

require_relative '../../integration_helper'
require 'generators/solid_terminator/update_generator'

RSpec.describe SolidTerminator::Generators::UpdateGenerator do
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

  it 'does not create the initializer' do
    run_generator
    expect(File).not_to exist(File.join(destination, 'config/initializers/solid_terminator.rb'))
  end

  context 'when upgrading an install made before the arguments column existed' do
    let(:old_migration) { Dir[File.join(destination, 'db/migrate/*_create_solid_queue_terminations.rb')].first }

    before do
      SolidTerminator::Generators::InstallGenerator.start(['--quiet'], destination_root: destination)
      FileUtils.rm(Dir[File.join(destination, 'db/migrate/*_add_arguments_*.rb')])
      # Older installs were generated under another Rails version, so their files are not identical.
      Dir[File.join(destination, 'db/migrate/*.rb')].each do |path|
        File.write(path, File.read(path).sub(/Migration\[[\d.]+\]/, 'Migration[7.0]'))
      end
    end

    it 'adds only the missing migration' do
      run_generator
      expect(migrations).to match_array(all_migrations)
    end

    it 'leaves existing migrations untouched' do
      expect { run_generator }.not_to(change { File.read(old_migration) })
    end
  end

  context 'when every migration is already installed' do
    before { run_generator }

    it 'does not add any migration' do
      run_generator
      expect(migrations).to match_array(all_migrations)
    end
  end
end
