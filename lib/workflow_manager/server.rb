#!/usr/bin/env ruby
# encoding: utf-8

require 'drb/drb' 
require 'fileutils'
begin
  require 'kyotocabinet'
  NO_KYOTO = false
rescue LoadError
  require 'pstore'
  class PStore
    def each
      self.roots.each do |key|
        yield(key, self[key])
      end
    end
  end
  NO_KYOTO = true
end

module WorkflowManager
  # default parameters
  LOG_DIR  = 'logs'
  DB_DIR   = 'dbs'
  INTERVAL = 30
  RESUBMIT = 0

  class Server
    @@config = nil
    class Config
      attr_accessor :log_dir
      attr_accessor :db_dir
      attr_accessor :interval
      attr_accessor :resubmit
      attr_accessor :cluster
    end
    def self.config=(config)
      @@config = config
    end
    def self.config
      @@config
    end
    def config
      @@config ||= WorkflowManager.configure{}
    end
    def self.configure
      @@config = Config.new
      # default values
      @@config.log_dir  = LOG_DIR
      @@config.db_dir   = DB_DIR
      @@config.interval = INTERVAL  # interval to check jobs, [s]
      @@config.resubmit = RESUBMIT  # how many times at maximum to resubmit when job fails
      yield(@@config)
      if @@config.cluster
        @@config.cluster.log_dir = File.expand_path(@@config.log_dir)
      end
      @@config
    end

    class KyotoDB
      def initialize(db_file)
        @file = db_file
        @db = KyotoCabinet::DB.new
      end
      def transaction
        @db.open(@file)
        yield(@db)
        @db.close
      end
    end
    class PStoreDB 
      def initialize(db_file)
        @db = PStore.new(db_file)
      end
      def transaction
        @db.transaction do 
          yield(@db)
        end
      end
    end

    def initialize
      @interval = config.interval
      @resubmit = config.resubmit
      extension = NO_KYOTO ? '.pstore' : '.kch'
      db_mode = NO_KYOTO ? 'PStore' : 'KyotoCabinet'
      @db_stat = File.join(config.db_dir, 'statuses'+extension)
      @db_logs  = File.join(config.db_dir, 'logs'+extension)

      @log_dir = File.expand_path(config.log_dir)
      @db_dir  = File.expand_path(config.db_dir)
      FileUtils.mkdir_p @log_dir unless File.exist?(@log_dir)
      FileUtils.mkdir_p @db_dir unless File.exist?(@db_dir)
      #@statuses = KyotoCabinet::DB.new
      @statuses = NO_KYOTO ? PStoreDB.new(@db_stat) : KyotoDB.new(@db_stat)
      #@logs = KyotoCabinet::DB.new 
      @logs = NO_KYOTO ? PStoreDB.new(@db_logs) : KyotoDB.new(@db_logs)
      @system_log = File.join(@log_dir, "system.log")
      @mutex = Mutex.new
      @cluster = config.cluster
      puts("DB = #{db_mode}")
      puts("Cluster = #{@cluster.name}")
      log_puts("DB = #{db_mode}")
      log_puts("Cluster = #{@cluster.name}")
      log_puts("Server starts")
    end
    def hello
      'hello, '+ @cluster.name
    end
    def copy_commands(org_dir, dest_parent_dir, now=nil)
      @cluster.copy_commands(org_dir, dest_parent_dir, now)
    end
    def kill_job(job_id)
      status(job_id, 'fail')
      status = `#{@cluster.kill_command(job_id)}`
    end
    def delete_command(target)
      @cluster.delete_command(target)
    end
    def log_puts(str)
      time = Time.now.strftime("[%Y.%m.%d %H:%M:%S]")
      @mutex.synchronize do
         open(@system_log, "a") do |out|
           out.print time + " " + str + "\n"
         end
      end
    end
    def start_monitoring(submit_command, user = 'sushi lover', resubmit = 0, script = '', project_number = 0, sge_options='', log_dir = '')
      log_puts("monitoring: script=" + submit_command + " user=" + user + " resubmit=" + resubmit.to_s + " project=" + project_number.to_s + " sge option=" + sge_options + " log dir=" + log_dir.to_s)

      #warn submit_command
      #
      # TODO: analyze arguments
      #
      job_id, log_file, command = @cluster.submit_job(submit_command, script, sge_options)
      log_puts("submit: " + job_id + " " + command)

      #
      # monitor worker
      #
      if job_id and log_file
        monitor_worker = Thread.new(job_id, log_file, submit_command, user, resubmit, script, project_number, sge_options, log_dir) do |t_job_id, t_log_file, t_submit_command, t_user, t_resubmit, t_script, t_project_number, t_sge_options, t_log_dir|
          loop do
            status = success_or_fail(t_job_id, t_log_file) 
            script_name = File.basename(submit_command).split(/-/).first
            #@statuses.open(@db_stat)
            @statuses.transaction do |statuses|
            #start_time = if stat = @statuses[t_job_id] and stat = stat.split(/,/) and time = stat[2]
              start_time = if stat = statuses[t_job_id] and stat = stat.split(/,/) and time = stat[2]
                             time
                           end
              time = if start_time 
                       if status == 'success' or status == 'fail'
                         start_time + '/' + Time.now.strftime("%Y-%m-%d %H:%M:%S")
                       else
                         start_time
                       end
                     else
                       Time.now.strftime("%Y-%m-%d %H:%M:%S")
                     end
            #@statuses[t_job_id] = [status, script_name, time, user, project_number].join(',')
              statuses[t_job_id] = [status, script_name, time, user, project_number].join(',')
            #@statuses.close
            end
            @logs.transaction do |logs|
              logs[t_job_id] = t_log_file
            end
            #warn t_job_id + " " + status
            if status == 'success'
              log_puts(status + ": " + t_job_id)
              unless t_log_dir.empty?
                copy_commands(t_log_file, t_log_dir).each do |command|
                  log_puts(command)
                  system command
                end
                err_file = t_log_file.gsub('_o.log','_e.log')
                copy_commands(err_file, t_log_dir).each do |command|
                  log_puts(command)
                  system command
                end
              end
              Thread.current.kill
            elsif status == 'fail'
              log_puts(status + ": " + t_job_id)
              #
              # TODO: re-submit
              #
              if t_resubmit < RESUBMIT
                log_puts("resubmit: " + t_job_id)
                resubmit_job_id = start_monitoring(t_submit_command, t_user, t_resubmit + 1, t_script, t_project_number, t_sge_options)
                script_name = File.basename(submit_command).split(/-/).first
                #@statuses.open(@db_stat)
                @statuses.transaction do |statuses|
                  statuses[t_job_id] = ["resubmit: " + resubmit_job_id.to_s, script_name, Time.now.strftime("%Y-%m-%d %H:%M:%S"), t_user, t_project_number].join(',')
                #@statuses.close
                end
              else
                log_puts("fail: " + t_job_id)
              end
              unless t_log_dir.empty?
                copy_commands(t_log_file, t_log_dir).each do |command|
                  log_puts(command)
                  system command
                end
                err_file = t_log_file.gsub('_o.log','_e.log')
                copy_commands(err_file, t_log_dir).each do |command|
                  log_puts(command)
                  system command
                end
              end
              Thread.current.kill
            end
            sleep @interval
          end	
        end
        job_id.to_i
      end
    end
    def status(job_id, new_status=nil)
      stat = nil
      #@statuses.open(@db_stat)
      @statuses.transaction do |statuses|
        if new_status and stat = statuses[job_id.to_s]
          status_list = ['success', 'running', 'fail']
          if status_list.include?(new_status)
            items = stat.split(/,/)
            items.shift
            items.unshift(new_status)
            stat = items.join(',')
            statuses[job_id.to_s] = stat
          end
        else
          stat = statuses[job_id.to_s]
        end
      end
      #@statuses.close
      stat
    end
    def job_list(with_results=false, project_number=nil)
      s = []
      #@statuses.open(@db_stat)
      @statuses.transaction do |statuses|
        statuses.each do |key, value|
          if project_number 
            if x = value.split(/,/)[4].to_i==project_number.to_i
              s << [key, value]
            end
          else
            s << [key, value]
          end
        end
      #@statuses.close
      end
      s.sort_by{|i| i.split(',')[3]}.reverse.map{|v| v.join(',')}.join("\n")
    end
    def get_log(job_id, with_err=false)
      log_file = nil
      @logs.transaction do |logs|
        log_file = logs[job_id.to_s]
      end
      log_data = if log_file and File.exist?(log_file)
                   "__STDOUT LOG__\n\n" + File.read(log_file)
                 else
                   'no log file'
                 end
      if with_err
        err_file = log_file.gsub(/_o\.log/,'_e.log')
        if err_file and File.exist?(err_file)
          log_data << "\n\n__STDERR LOG__\n\n"
          log_data << File.read(err_file)
        end
      end
      log_data
    end
    def get_script(job_id)
      script_file = nil
      @logs.transaction do |logs|
        script_file = logs[job_id.to_s]
      end
      if script_file
        script_file = script_file.gsub(/_o\.log/,'')
      end
      script = if script_file and File.exist?(script_file)
                 File.read(script_file)
               else
                 'no script file'
               end
      script
    end
    def success_or_fail(job_id, log_file)
      job_running = @cluster.job_running?(job_id)
      job_ends = @cluster.job_ends?(log_file)
      msg = if job_running
              'running'
            elsif job_ends
              'success'
            else
              'fail'
            end
      msg
    end
  end
end

