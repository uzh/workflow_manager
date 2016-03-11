#!/usr/bin/env ruby
# encoding: utf-8

require './lib/workflow_manager/cluster'

include WorkflowManager
describe Cluster do
  subject(:cluster) {Cluster.new}
  context 'when new' do
    it {is_expected.to be_an_instance_of Cluster} # RSpec3
#    it {should be_an_instance_of Cluster} # RSpec2
#    example {expect(cluster).to be_an_instance_of Cluster} # RSpec3
#    its(:options) {should be_empty} # RSpec2, does not work anymore
#    example {expect(cluster.options).to be_empty}
  end 
  describe '#job_running?' do
    subject {cluster.job_running?('job_id')}
    it {is_expected.to be_nil}
  end
  describe '#job_ends?' do
    subject {cluster.job_ends?('log_file')}
    it {is_expected.to be_nil}
  end
  describe '#job_pending?' do
    subject {cluster.job_pending?('job_id')}
    it {is_expected.to be_nil}
  end
end

describe FGCZCluster do
  subject(:cluster) {FGCZCluster.new}
  context 'when new' do
    it {is_expected.to be_an_instance_of FGCZCluster}
  end
  describe '#job_running?' do
    let(:line) {'  72757 0.50661 Gcal017211 pacbio       r     03/11/2016'}
    let(:job_id) {'72757'}
    subject {cluster.job_running?(job_id)}
    let(:io) {double('io')}
    before do
      allow(IO).to receive(:popen).and_yield(io)
    end
    context 'when running' do
      before do
        allow(io).to receive(:gets).and_return(line)
      end
      it {is_expected.to eq true}
    end
    context 'when not running?' do
      before do
        allow(io).to receive(:gets).and_return(nil)
      end
      it {is_expected.to eq false}
    end
  end
  describe '#job_ends?' do
    let(:log_file) {'log_file'}
    subject {cluster.job_ends?(log_file)}
    let(:io) {double('io')}
    before do
      allow(IO).to receive(:popen).and_yield(io)
    end
    context 'when job ends' do
      before do
        allow(io).to receive(:gets).and_return('__SCRIPT END__')
      end
      it {is_expected.to eq true}
    end
    context 'when job not ends' do
      before do
        allow(io).to receive(:gets).and_return(nil)
      end
      it {is_expected.to eq false}
    end
  end
  describe '#job_pending?' do
    let(:job_id) {'1234'}
    let(:line) {'  1234 0.50661 Gcal017211 pacbio       qw     03/11/2016'}
    subject {cluster.job_pending?(job_id)}
    let(:io) {double('io')}
    before do
      allow(IO).to receive(:popen).and_yield(io)
    end
    context 'when pending' do
      before do
        allow(io).to receive(:gets).and_return(line)
      end
      it {is_expected.to eq true}
    end
    context 'when not pending' do
      before do
        allow(io).to receive(:gets).and_return(nil)
      end
      it {is_expected.to eq false}
    end
  end
end
