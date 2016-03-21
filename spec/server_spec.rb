#!/usr/bin/env ruby
# encoding: utf-8

require './lib/workflow_manager/server'

include WorkflowManager
describe Server do
  subject(:server) {Server.new}
  let(:cluster){double('local_computer')}
  before do
    WorkflowManager::Server.configure do |config|
      config.log_dir = '/srv/GT/analysis/masaomi/workflow_manager/run_workflow_manager/logs'
      config.db_dir = '/srv/GT/analysis/masaomi/workflow_manager/run_workflow_manager/dbs'
      config.interval = 30
      config.resubmit = 0
      #config.cluster = WorkflowManager::LocalComputer.new('local_computer')
      config.cluster = cluster
      allow(config.cluster).to receive_messages(:log_dir= => nil, :name => 'local_computer')
    end
    # suppress puts
    allow($stdout).to receive(:write)
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
  describe '#start_monitoring2' do
    let(:script_path){'script_file'}
    let(:script_content){'script_content'}
    let(:cluster){double('cluster')}
    before do
      allow(server).to receive(:input_dataset_tsv_path)
      allow(server).to receive(:input_dataset_file_list)
      allow(server).to receive(:input_dataset_exist?)
    end
    context 'when submit_job failed' do
      before do
        allow(cluster).to receive(:submit_job)
      end
      subject {server.start_monitoring2(script_path, script_content)}
      it {is_expected.to be_nil}
    end
    context 'when submit_job successed' do
      pending
=begin
      let(:waiting_time){0}
      before do
        allow(cluster).to receive(:submit_job).and_return(['job_id', 'log_file', 'command'])
        allow(Thread).to receive(:new).and_yield('log_file', 'log_dir', 'script_path', waiting_time)
        allow(server).to receive(:input_dataset_exist?).and_return(true)
        allow(cluster).to receive(:submit_job).and_return('job_id', 'log_file','command')
        allow(server).to receive(:check_status)
        allow(server).to receive(:update_time_status)
        allow(server).to receive(:finalize_monitoring)
      end
      subject {server.start_monitoring2(script_path, script_content)}
      it {is_expected.to eq 'job_id'}
=end
    end
    context 'when input dataset does not exist' do
      pending
    end
  end
  describe '#success_or_fail' do
    let(:job_id){'job_id'}
    let(:log_file){'log_file'}
    let(:cluster){double('cluster')}
    before do
      server.instance_variable_set(:@cluster, cluster)
    end
    context 'when job running' do
      before do
        allow(cluster).to receive(:job_running?).and_return(true)
        allow(cluster).to receive(:job_ends?).and_return(nil)
        allow(cluster).to receive(:job_pending?).and_return(nil)
      end
      subject {server.success_or_fail(job_id, log_file)}
      it {is_expected.to eq 'running'}
    end
    context 'when job ends' do
      before do
        allow(cluster).to receive(:job_running?).and_return(nil)
        allow(cluster).to receive(:job_ends?).and_return(true)
        allow(cluster).to receive(:job_pending?).and_return(nil)
      end
      subject {server.success_or_fail(job_id, log_file)}
      it {is_expected.to eq 'success'}
    end
    context 'when job pending' do
      before do
        allow(cluster).to receive(:job_running?).and_return(nil)
        allow(cluster).to receive(:job_ends?).and_return(nil)
        allow(cluster).to receive(:job_pending?).and_return(true)
      end
      subject {server.success_or_fail(job_id, log_file)}
      it {is_expected.to eq 'pending'}
    end
  end
  describe '#status' do
    let(:statuses) {double('statuses')}
    before do 
      server.instance_variable_set(:@statuses, statuses)
    end
    context 'when read status' do 
      before do
        allow(statuses).to receive(:transaction).and_yield({'job_id'=>'stat'})
      end
      subject {server.status('job_id')}
      it {is_expected.to eq 'stat'}
    end
    context 'when assign status' do
      before do
        allow(statuses).to receive(:transaction).and_yield({'job_id'=>'running'})
      end
      subject {server.status('job_id', 'success')}
      it {is_expected.to eq 'success'}
    end
  end
  describe '#update_time_status' do
    let(:statuses) {double('statuses')}
    before do 
      server.instance_variable_set(:@statuses, statuses)
    end
    context 'when initial call' do
      before do
        allow(statuses).to receive(:transaction).and_yield({'job_id' => nil})
        allow(Time).to receive_message_chain(:now, :strftime).and_return('time')
      end
      let(:expected) {'current_status,script_name,time,user,project_number'}
      subject {server.update_time_status('job_id', 'current_status', 'script_name', 'user', 'project_number')}
      it {is_expected.to eq expected}
    end
    context 'when changing status from running to success' do
      let(:last_status) {'running,script_name,start_time,user,project_number'}
      before do
        allow(statuses).to receive(:transaction).and_yield({'job_id' => last_status})
        allow(Time).to receive_message_chain(:now, :strftime).and_return('end_time')
      end
      subject {server.update_time_status('job_id', 'success', 'script_name', 'user', 'project_number')}
      let(:expected) {'success,script_name,start_time/end_time,user,project_number'}
      it {is_expected.to eq expected}
    end
    context 'when current_status and new_sutatus are same' do
      let(:last_status) {'running,script_name,start_time,user,project_number'}
      before do
        allow(statuses).to receive(:transaction).and_yield({'job_id' => last_status})
        allow(Time).to receive_message_chain(:now, :strftime).and_return('end_time')
      end
      subject {server.update_time_status('job_id', 'running', 'script_name', 'user', 'project_number')}
      it {is_expected.to be_nil}
    end
    context 'when current_status==running and last_status==pending' do
      let(:last_status) {'pending,script_name,start_time,user,project_number'}
      before do
        allow(statuses).to receive(:transaction).and_yield({'job_id' => last_status})
        allow(Time).to receive_message_chain(:now, :strftime).and_return('end_time')
      end
      subject {server.update_time_status('job_id', 'running', 'script_name', 'user', 'project_number')}
      let(:expected) {"running,script_name,end_time,user,project_number"}
      it {is_expected.to eq expected}
    end
  end
  describe '#finalize_monitoring' do
    context 'when status == running' do
      before do
        allow(server).to receive(:log_puts)
        allow(Thread).to receive_message_chain(:current, :kill)
      end
      subject {server.finalize_monitoring('running', 'log_file', 'log_dir')}
      it {is_expected.to be_nil}
    end
    context 'when status == success' do
      before do
        allow(server).to receive(:log_puts)
        allow(Thread).to receive_message_chain(:current, :kill)
        #expect(server).to receive(:system).twice
        expect(server).to receive(:copy_commands).twice.and_return([])
      end
      subject {server.finalize_monitoring('success', 'log_file', 'log_dir')}
      it {is_expected.to be_nil}
    end
  end
end
