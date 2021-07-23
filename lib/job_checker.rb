require 'sidekiq'
require 'redis'

WORKER_INTERVAL = 10 # [s]

Sidekiq.configure_server do |config|
  config.redis = { url: 'redis://localhost:6380/3' }
end

Sidekiq.configure_client do |config|
  config.redis = { url: 'redis://localhost:6380/3' }
end

class Redis
  alias_method :[], :get
  alias_method :[]=, :set
end

class JobWorker
  include Sidekiq::Worker
  sidekiq_options queue: :default, retry: 5

  def generate_new_job_script(log_dir, script_basename, script_content)
    new_job_script = File.basename(script_basename) + "_" + Time.now.strftime("%Y%m%d%H%M%S%L")
    new_job_script = File.join(log_dir, new_job_script)
    open(new_job_script, 'w') do |out|
      out.print script_content
      out.print "\necho __SCRIPT END__\n"
    end
    new_job_script
  end
  def update_time_status(status, script_basename, user, project_number)
    unless @start_time
      @start_time = Time.now.strftime("%Y-%m-%d %H:%M:%S")
    end
    time = Time.now.strftime("%Y-%m-%d %H:%M:%S")
    [status, script_basename, [@start_time, time].join("/"), user, project_number].join(',')
  end

  def perform(job_id, script_basename, log_file, user, project_id)
    puts "JobID: #{job_id}"
    db0 = Redis.new(port: 6380, db: 0) # state + alpha DB
    db1 = Redis.new(port: 6380, db: 1) # log DB
    db2 = Redis.new(port: 6380, db: 2) # project jobs DB
    db1[job_id] = log_file
    pre_state = nil
    @start_time = nil
    begin
      command = "sacct --jobs=#{job_id} --format=state"
      #puts command
      ret = `#{command}`
      #print ret
      state = ret.split(/\n/).last.strip
      #puts "state: #{state}"
      db0[job_id] = update_time_status(state, script_basename, user, project_id)

      unless state == pre_state
        db0[job_id] = update_time_status(state, script_basename, user, project_id)
        project_jobs = eval((db2[project_id]||[]).to_s)
        project_jobs = Hash[*project_jobs]
        project_jobs[job_id] = state
        #p project_jobs
        db2[project_id] = project_jobs.to_a.flatten.last(200).to_s
      end
      pre_state = state
      sleep WORKER_INTERVAL
    end while state =~ /RUNNING/  or state =~ /PENDING/ or state =~ /---/
  end
end

