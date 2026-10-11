# frozen_string_literal: true

require_relative 'lib/solid_terminator/version'

Gem::Specification.new do |spec|
  spec.name    = 'solid_terminator'
  spec.version = SolidTerminator::VERSION
  spec.authors = ['Meszaros Istvan-Abel']
  spec.email   = ['meszarosistvan97@gmail.com']

  spec.summary     = 'Terminate specific in-progress SolidQueue jobs without stopping the worker'
  spec.description = 'Adds per-job termination to SolidQueue via a monitor thread and Thread#raise'
  spec.homepage    = 'https://github.com/IstvanMs/solid_terminator'
  spec.license     = 'MIT'

  spec.required_ruby_version = '>= 3.1'

  spec.files = Dir['lib/**/*', 'LICENSE.txt', 'README.md', 'CHANGELOG.md']

  spec.require_paths = ['lib']

  spec.add_dependency 'activejob',    '>= 7.1'
  spec.add_dependency 'activerecord', '>= 7.1'
  spec.add_dependency 'railties',     '>= 7.1'
  spec.add_dependency 'solid_queue',  '>= 1.0'

  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.metadata['source_code_uri']       = 'https://github.com/IstvanMs/solid_terminator'
  spec.metadata['bug_tracker_uri']       = 'https://github.com/IstvanMs/solid_terminator/issues'
  spec.metadata['changelog_uri']         = 'https://github.com/IstvanMs/solid_terminator/blob/main/CHANGELOG.md'
end
