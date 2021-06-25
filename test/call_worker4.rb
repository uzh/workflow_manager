#!/usr/bin/env ruby
# encoding: utf-8
# Version = '20210625-104318'

require './lib/worker4'
script_file = "./test/test_job1.sh"
script_content = File.read(script_file)
log_dir = "./logs"
script_basename = File.basename(script_file)
JobWorker.perform_async(1001, log_dir, script_basename, script_content)
p "submitted test_job1.sh"
