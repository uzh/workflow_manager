#!/usr/bin/env ruby
# encoding: utf-8

require 'drb/drb' 
require 'fileutils'
require 'csv'

require 'job_checker'

begin
  require 'redis'
  DB_MODE = "Redis"
  class Redis
    def [](key)
      self.get(key)
    end
    def []=(key, value)
      self.set(key, value)
    end
    def each
      self.scan_each do |key|
        value = self.get(key)
        yield([key, value])
      end
    end
  end
rescue LoadError
  begin
    require 'kyotocabinet'
    DB_MODE = "KyotoCabinet"
  rescue LoadError
    require 'pstore'
    DB_MODE = "PStore"
    class PStore
      def each
        self.roots.each do |key|
          yield(key, self[key])
        end
      end
    end
  end
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
      attr_accessor :redis_conf
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
    class RedisDB
      attr_accessor :port
      def run_redis_server(redis_conf)
        @pid = fork do
          exec("redis-server #{redis_conf}")
        end
        @redis_thread = Thread.new do
          Process.waitpid @pid
        end
      end
      def initialize(db_no=0, redis_conf)
        if db_no==0
          run_redis_server(redis_conf)
        end
        conf = Hash[*CSV.readlines(redis_conf, col_sep: " ").map{|a| [a.first, a[1,100].join(",")]}.flatten]
        @port = (conf["port"]||6379).to_i
        @db = Redis.new(port: @port, db: db_no)
      end
      def transaction
        #@db.multi do
          yield(@db)
        #end
      end
    end

    def initialize
      @interval = config.interval
      @resubmit = config.resubmit
      extension = case DB_MODE
                    when "PStore"
                      '.pstore'
                    when "KyotoCabinet"
                      '.kch'
                    when "Redis"
                      @redis_conf = config.redis_conf
                      '.rdb'
                    end
      @db_stat = File.join(config.db_dir, 'statuses'+extension)
      @db_logs  = File.join(config.db_dir, 'logs'+extension)

      @log_dir = File.expand_path(config.log_dir)
      @db_dir  = File.expand_path(config.db_dir)
      FileUtils.mkdir_p @log_dir unless File.exist?(@log_dir)
      FileUtils.mkdir_p @db_dir unless File.exist?(@db_dir)
      @statuses = case DB_MODE
                    when "PStore"
                      PStoreDB.new(@db_stat)
                    when "KyotoCabinet"
                      KyotoDB.new(@db_stat)
                    when "Redis"
                      RedisDB.new(0, @redis_conf)
                  end
      @logs = case DB_MODE
                  when "PStore"
                    PStoreDB.new(@db_logs)
                  when "KyotoCabinet"
                    KyotoDB.new(@db_logs)
                  when "Redis"
                    RedisDB.new(1, @redis_conf)
                end
      @jobs = RedisDB.new(2, @redis_conf)

      @system_log = File.join(@log_dir, "system.log")
      @mutex = Mutex.new
      @cluster = config.cluster
      puts("DB = #{DB_MODE}")
      if DB_MODE == "Redis"
        puts("Redis conf = #{config.redis_conf}")
        puts("Redis port = #{@logs.port}")
      end
      puts("Cluster = #{@cluster.name}")
      log_puts("DB = #{DB_MODE}")
      log_puts("Cluster = #{@cluster.name}")
      log_puts("Server starts")
      log_puts("Recovery check")
      sleep 2
      recovery_job_checker
    end
    def recovery_job_checker
      @logs.transaction do |logs|
      @statuses.transaction do |statuses|
        statuses.each do |job_id, status|
          # puts [job_id, status].join(",")
          # 120249,RUNNING,QC_ventricles_100k.sh,2021-07-30 09:47:04/2021-07-30 09:47:04,masaomi,1535
          stat, script_basename, time, user, project_number, next_dataset_id = status.split(",")
          if stat == "RUNNING" or stat == "PENDING"
            log_file = logs[job_id]
            log_puts("JobID (in recovery check): #{job_id}")
            puts "JobID (in recovery check): #{job_id}"
            JobChecker.perform_async(job_id, script_basename, log_file, user, project_number, next_dataset_id)
          end
        end
      end
      end
    end
    def hello
      'hello hoge hoge bar boo bundle, '+ @cluster.name
    end
    def copy_commands(org_dir, dest_parent_dir, now=nil)
      @cluster.copy_commands(org_dir, dest_parent_dir, now)
    end
    def kill_job(job_id)
      status(job_id, 'FAIL')
      status = `#{@cluster.kill_command(job_id)}`
    end
    def delete_command(target)
      @cluster.delete_command(target)
    end
    def cluster_nodes
      @cluster.cluster_nodes
    end
    def default_node
      @cluster.default_node.to_s
    end
    def log_puts(str)
      time = Time.now.strftime("[%Y.%m.%d %H:%M:%S]")
      @mutex.synchronize do
         open(@system_log, "a") do |out|
           out.print time + " " + str + "\n"
         end
      end
    end
    def input_dataset_tsv_path(script_content)
      gstore_dir = nil
      input_dataset_path = nil
      script_content.split(/\n/).each do |line|
        if line =~ /GSTORE_DIR=(.+)/
          gstore_dir = $1.chomp
        elsif line =~ /INPUT_DATASET=(.+)/
          input_dataset_path = $1.chomp
          break
        end
      end
      [gstore_dir, input_dataset_path]
    end
    def input_dataset_file_list(dataset_tsv_path)
      file_list = []
      CSV.foreach(dataset_tsv_path, :headers=>true, :col_sep=>"\t") do |row|
        row.each do |header, value|
          if header =~ /\[File\]/
            file_list << value
          end
        end
      end
      file_list
    end
    def input_dataset_exist?(file_list)
      flag = true
      file_list.each do |file|
        unless File.exist?(file)
          flag = false
          break
        end
      end
      flag
    end
    def update_time_status(job_id, current_status, script_name, user, project_number)
      # if the current status changed from last time, then save, otherwise do nothing
      # once status changes into success or fail, then the thread is expected to be killed in later process
      @statuses.transaction do |statuses|
        start_time = nil
        if stat = statuses[job_id] 
          last_status, script_name, start_time, user, project_number = stat.split(/,/)
        end
        time = if start_time 
                 if current_status == 'success' or current_status == 'fail'
                   start_time + '/' + Time.now.strftime("%Y-%m-%d %H:%M:%S")
                 elsif current_status != last_status
                   Time.now.strftime("%Y-%m-%d %H:%M:%S")
                 end
               else
                 Time.now.strftime("%Y-%m-%d %H:%M:%S")
               end
        if time
          statuses[job_id] = [current_status, script_name, time, user, project_number].join(',')
        end
      end
    end
    def finalize_monitoring(current_status, log_file, log_dir)
      if current_status == 'success' or current_status == 'fail'
        unless log_dir.empty?
          copy_commands(log_file, log_dir).each do |command|
            log_puts(command)
            system command
          end
          err_file = log_file.gsub('_o.log','_e.log')
          copy_commands(err_file, log_dir).each do |command|
            log_puts(command)
            system command
          end
        end
        Thread.current.kill
      end
    end
    def start_monitoring3(script_path, script_content, user='sushi_lover', project_number=0, sge_options='', log_dir='', next_dataset_id='')
      script_basename = File.basename(script_path)
      job_id, log_file, command = @cluster.submit_job(script_path, script_content, sge_options)
      #p command
      #p log_file
      #p job_id
      puts "JobID (in WorkflowManager): #{job_id}"
      sleep 1
      JobChecker.perform_async(job_id, script_basename, log_file, user, project_number, next_dataset_id)
      job_id
    end
    def start_monitoring2(script_path, script_content, user='sushi_lover', project_number=0, sge_options='', log_dir='')
      # script_path is only used to generate a log file name
      # It is not used to read the script contents
      go_submit = false
      waiting_time = 0
      gstore_dir, input_dataset_path = input_dataset_tsv_path(script_content)
      if gstore_dir and input_dataset_path
        waiting_max = 60*60*8 # 8h
        # wait until the files come
        until waiting_time > waiting_max or 
          File.exist?(input_dataset_path) and
          file_list = input_dataset_file_list(input_dataset_path) and
          file_list.map!{|file| File.join(gstore_dir, file)} and
          go_submit = input_dataset_exist?(file_list)
          sleep @interval
          waiting_time += @interval
        end
      end 

      job_id, log_file, command = if go_submit 
                                    @cluster.submit_job(script_path, script_content, sge_options)
                                  else
                                    raise "stop submitting #{File.basename(script_path)}, since waiting_time #{waiting_time} > #{waiting_max}"
                                  end

      if job_id and log_file 
        # save log_file in logs
        @logs.transaction do |logs|
          logs[job_id] = log_file
        end

        # job status check until it finishes with success or fail 
        worker = Thread.new(log_dir, script_path, script_content, sge_options) do |log_dir, script_path, script_content, sge_options|
          loop do
            # check status
            current_status = check_status(job_id, log_file)

            # save time and status
            update_time_status(job_id, current_status, script_path, user, project_number)

            # finalize (kill current thred) in case of success or fail 
            finalize_monitoring(current_status, log_file, log_dir)

            # wait
            sleep @interval
          end # loop
        end
        job_id
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
          status_list = ['CONPLETED', 'RUNNING', 'PENDING', 'FAIL']
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
    def job_list(with_results=false, project_number=nil, job_ids:nil)
      s = []
      job_idsh = if job_ids
                   Hash[*(job_ids.split(',')).map{|job_id| [job_id, true]}.flatten]
                 end
      if project_number
        s_ = {}
        @jobs.transaction do |jobs|
          if project_jobs = jobs[project_number]
            s_ = Hash[*eval(project_jobs)]
          end
        end
        @statuses.transaction do |statuses|
          s_.each do |job_id, stat|
            s << [job_id, statuses[job_id]]
          end
        end
      else
        @statuses.transaction do |statuses|
          statuses.each do |key, value|
            s << [key, value]
          end
        end
      end
      if job_ids
        s = s.select{|job_id, stat| job_idsh[job_id]}
      end
      s.sort_by{|key, value| value.split(',')[2]}.reverse.map{|v| v.join(',')}.join("\n")
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
    def get_script_path(job_id)
      script_file = nil
      @logs.transaction do |logs|
        script_file = logs[job_id.to_s]
      end
      script_path = if script_file and File.exist?(script_file)
                      script_file.gsub(/_o\.log/,'')
                    end
    end
    def success_or_fail(job_id, log_file)
      msg = if @cluster.job_running?(job_id)
              'running'
            elsif @cluster.job_ends?(log_file)
              'success'
            elsif @cluster.job_pending?(job_id)
              'pending'
            else
              'fail'
            end
    end
    alias_method :check_status, :success_or_fail
    def cluster_node_list
      @cluster.node_list
    end
  end
end

