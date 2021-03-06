# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'heroku_helper/version'

Gem::Specification.new do |spec|
  spec.name          = 'heroku-platform-helper'
  spec.version       = HerokuHelper::VERSION
  spec.authors       = ['Paul Robertson']
  spec.email         = ['t.paulrobertson@gmail.com']

  spec.summary       = 'A helper library for managing Heroku apps.'
  spec.homepage      = 'https://github.com/perobertson/heroku-platform-helper'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.10'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'codeclimate-test-reporter'
  spec.add_development_dependency 'byebug'
  spec.add_development_dependency 'rubocop'

  spec.add_dependency 'platform-api', '~> 0.3'
  spec.add_dependency 'rendezvous', '~> 0.1'
  spec.add_dependency 'git', '>= 1.2.6'
end
