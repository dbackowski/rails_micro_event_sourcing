# frozen_string_literal: true

require_relative 'lib/rails_micro_event_sourcing/version'

Gem::Specification.new do |spec|
  spec.name        = 'rails_micro_event_sourcing'
  spec.version     = RailsMicroEventSourcing::VERSION
  spec.authors     = ['Damian Baćkowski']
  spec.email       = ['damianbackowski@gmail.com']
  spec.homepage    = 'https://github.com/dbackowski/rails_micro_event_sourcing'
  spec.summary     = 'Minimal event sourcing for Rails: the event is the model.'
  spec.description = 'A tiny Rails engine for event sourcing. Each event is an ' \
                     'ActiveRecord model that validates itself and, on save, ' \
                     'applies its change to the related aggregate. No commands, ' \
                     'no handlers, no bus.'
  spec.license               = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/dbackowski/rails_micro_event_sourcing'

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir['{app,config,db,lib}/**/*', 'MIT-LICENSE', 'Rakefile', 'README.md']
  end

  spec.add_dependency 'pg', '~> 1.1'
  spec.add_dependency 'rails', '>= 7.1'
  spec.add_development_dependency 'rubocop'
  spec.add_development_dependency 'rubocop-rails'
end
