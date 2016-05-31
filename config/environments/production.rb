#!/usr/bin/env ruby
# encoding: utf-8

WorkflowManager::Server.configure do |config|
  config.log_dir = 'logs'
  config.db_dir = 'dbs'
  config.interval = 30
  config.resubmit = 0
  config.cluster = WorkflowManager::FGCZCluster.new('FGCZCluster')
end

