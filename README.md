# WorkflowManager

This library is a server/client application through dRuby protocol. Mainly it is expected to be used with [SUSHI](https://github.com/uzh/sushi) and [SushiFabric](https://github.com/uzh/sushi_fabric). However, it is possible to use it independently from [SUSHI](https://github.com/uzh/sushi). The main function is to create a worker thread to observe a submitted job by calling a server side function from a client.

## Installation

Add this line to your application's Gemfile:

    gem 'workflow_manager'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install workflow_manager

## Usage

Server starts
~~~~
  $ workflow_manager -h                                                                                   16-05-10 15:56
  Usage:
   workflow_manager -d [druby://host:port] -m [development|production]
      -d, --server server              workflow manager URI (default: druby://localhost:12345)
      -m, --mode mode                  development|production (default: development)
~~~~

At the first execution, automatically the configulation file similar to the one of Ruby on Rails are generated in config directory as follows:

config/environments/development.rb
~~~~
#!/usr/bin/env ruby
# encoding: utf-8

WorkflowManager::Server.configure do |config|
  config.log_dir = 'logs'
  config.db_dir = 'dbs'
  config.interval = 30
  config.resubmit = 0
  config.cluster = WorkflowManager::LocalComputer.new('LocalComputer')
end
~~~~

After installation, the following client commands become availabe:

* wfm_delete_command
* wfm_get_log
* wfm_get_script
* wfm_hello
* wfm_job_list
* wfm_kill_job
* wfm_monitoring
* wfm_status

In order to submit a job script, call wfm_monitoring command:

~~~~
$ wfm_monitoring -h                                                                                     16-05-10 16:03
Usage:
 wfm_monitoring [options] [job_script.sh]
    -u, --user user                  who submitted? (default: sushi lover)
    -p, --project project            project number (default: 1001)
    -d, --server server              workflow manager URI (default: druby://localhost:12345)
~~~~

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
