# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'workflow_manager/version'

Gem::Specification.new do |spec|
  spec.name          = "workflow_manager"
  spec.version       = WorkflowManager::VERSION
  spec.authors       = ["Functional Genomics Center Zurich"]
  spec.email         = ["masaomi.hatakeyama@fgcz.uzh.ch"]
  spec.description   = %q{Workflow Manager manages job submissions using dRuby.}
  spec.summary       = %q{Workflow Manager manages job submissions using dRuby.}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  #spec.files         = `bzr ls --versioned --recursive`.split($/).select{|file| !File.directory?(file)}
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 2.2.10"
  spec.add_development_dependency "rake"
end
