#!/usr/bin/env ruby
# encoding: utf-8

WorkflowManager.configure do |config|
  config.log_dir = 'logs'
  config.db_dir = 'dbs'
  config.interval = 30
  config.resubmit = 0
  config.cluster = LocalComputer.new('local_computer')
end

