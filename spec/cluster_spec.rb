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
end
