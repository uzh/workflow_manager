#!/usr/bin/env ruby
# encoding: utf-8
# Version = '20210618-142727'

require './lib/worker4'
script_content = File.read("./test/test_job1.sh")
log_dir = "./logs"
JobWorker.perform_async(1001, log_dir, script_content)
p "submitted test_job1.sh"
