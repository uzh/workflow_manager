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
  describe '#input_dataset_exist?' do
    pending 
  end
  describe '#input_dataset_file_list' do
    pending
  end
  describe '#input_dataset_tsv_path' do
    let(:sample_script) {
      "SCRATCH_DIR=/scratch/test_masa_2016-03-03--16-36-42_temp$$
GSTORE_DIR=/srv/gstore/projects
INPUT_DATASET=/srv/gstore/projects/p1535/test_masa/input_dataset.tsv"
    }
    let(:path){
      '/srv/gstore/projects/p1535/test_masa/input_dataset.tsv'
    }
    subject{server.input_dataset_tsv_path(sample_script)}
    it {is_expected.to eq path}
  end
end
