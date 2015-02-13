# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'Mockerize/version'

Gem::Specification.new do |spec|
  spec.name          = 'Mockerize'
  spec.version       = Mockerize::VERSION
  spec.authors       = ['Miguel Alonso Jr']
  spec.email         = ['drmiguelalonsojr@gmail.com']
  spec.summary       = %q{Mockerize is a mock authorize.net customer information management (CIM) class for Rails.}
  spec.description   = %q{Mockerize is a mock authorize.net customer information management (CIM) class for Rails. It is based on the active-merchant (http://activemerchant.org) authorize.net CIM gateway. It use Redis as a data store to simulate the authorize.net CIM service.}
  spec.homepage      = ''
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.7'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'activemerchant'
  spec.add_development_dependency 'redis'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'shoulda-matchers'
  # spec.add_development_dependecy 'null_logger'
end
