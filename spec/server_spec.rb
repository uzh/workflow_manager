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
    let(:file_list) {['file1', 'file2']}
    subject{server.input_dataset_exist?(file_list)}
    context 'when file exist' do 
      before do
        allow(File).to receive(:exist?).and_return(true)
      end
      it {is_expected.to eq true}
    end
    context 'when file not exist' do
      before do
        allow(File).to receive(:exist?).and_return(false)
      end
      it {is_expected.to eq false}
    end
  end
  describe '#input_dataset_file_list' do
      subject{server.input_dataset_file_list('input_dataset_tsv_path')}
      let(:rows) {{'Read1 [File]'=>'file1', 'Read2 [File]'=>'file2'} }
      before do
        allow(CSV).to receive(:foreach).and_yield(rows)
      end
      let(:sample_file_list) { ['file1', 'file2'] }
      it {is_expected.to eq sample_file_list}
  end
  describe '#input_dataset_tsv_path' do
    let(:sample_script) {
      "SCRATCH_DIR=/scratch/test_masa_2016-03-03--16-36-42_temp$$
GSTORE_DIR=/srv/gstore/projects
INPUT_DATASET=/srv/gstore/projects/p1535/test_masa/input_dataset.tsv"
    }
    let(:path){
      [
        '/srv/gstore/projects',
        '/srv/gstore/projects/p1535/test_masa/input_dataset.tsv'
      ]
    }
    subject{server.input_dataset_tsv_path(sample_script)}
    it {is_expected.to eq path}
  end
end
