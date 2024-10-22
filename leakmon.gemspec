# -*- encoding: utf-8 -*-
require File.expand_path('../lib/leakmon/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Mitsunori Komatsu"]
  gem.email         = ["komamitsu@gmail.com"]
  gem.description   = %q{A Ruby library to monitor leaked objects}
  gem.summary       = %q{A Ruby library to monitor leaked objects}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "leakmon"
  gem.require_paths = ["lib"]
  gem.version       = Leakmon::VERSION
  gem.add_development_dependency "rspec", "~> 2.13.0"
end
