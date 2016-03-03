#!/usr/bin/env ruby
# encoding: utf-8

require './lib/workflow_manager/server'

include WorkflowManager
describe Server do
  subject(:server) {Server.new}
  before do
    WorkflowManager::Server.configure do |config|
      config.log_dir = '/srv/GT/analysis/masaomi/workflow_manager/run_workflow_manager/logs'
      config.db_dir = '/srv/GT/analysis/masaomi/workflow_manager/run_workflow_manager/dbs'
      config.interval = 30
      config.resubmit = 0
      #config.cluster = WorkflowManager::LocalComputer.new('local_computer')
      config.cluster = double('local_computer')
      allow(config.cluster).to receive_messages(:log_dir= => nil, :name => 'local_computer')
    end
  end
  context 'when new' do
    it {is_expected.to be_an_instance_of Server} # RSpec3
  end 
end
