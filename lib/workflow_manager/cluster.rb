#!/usr/bin/env ruby
# encoding: utf-8

module WorkflowManager
  class Cluster
    attr_accessor :name
    attr_reader :options
    attr_accessor :log_dir
    def initialize(name='', log_dir='')
      @name = name
      @options = {}
      @log_dir = log_dir
    end
    def generate_new_job_script(script_name, script_content)
      new_job_script = File.basename(script_name) + "_" + Time.now.strftime("%Y%m%d%H%M%S")
      new_job_script = File.join(@log_dir, new_job_script)
      open(new_job_script, 'w') do |out|
        out.print script_content
        out.print "\necho __SCRIPT END__\n"
      end
      new_job_script
    end
    def submit_job(script_file, script_content, option='')
    end
    def job_running?(job_id)
    end
    def job_ends?(log_file)
    end
    def copy_commands(org_dir, dest_parent_dir, now=nil)
    end
    def kill_command(job_id)
    end
    def delete_command(target)
    end
  end

  class LocalComputer < Cluster
    def submit_job(script_file, script_content, option='')
      if script_name = File.basename(script_file) and script_name =~ /\.sh$/
        new_job_script = generate_new_job_script(script_name, script_content)
        new_job_script_base = File.basename(new_job_script)
        log_file = File.join(@log_dir, new_job_script_base + "_o.log")
        err_file = File.join(@log_dir, new_job_script_base + "_e.log")
        command = "bash #{new_job_script} 1> #{log_file} 2> #{err_file}"
        pid = spawn(command)
        Process.detach(pid)
        [pid.to_s, log_file, command]
      end
    end
    def job_running?(pid)
      command = "ps aux"
      result = IO.popen(command) do |io|
        flag = false
        while line=io.gets
          x = line.split
          if x[1].to_i == pid.to_i
            flag = true
            break
          end
        end
        flag
      end
      result
    end
    def job_ends?(log_file)
      command = "tail -n 20 #{log_file}|grep '__SCRIPT END__'"
      result = `#{command}`
      result.to_s.empty? ? false : true
    end
    def copy_commands(org_dir, dest_parent_dir, now=nil)
      commands = []
      commands << "mkdir -p #{dest_parent_dir}"
      commands << "cp -r #{org_dir} #{dest_parent_dir}"
      commands
    end
    def kill_command(job_id)
      command = "kill #{job_id}"
    end
    def delete_command(target)
      command = "rm -rf #{target}"
    end
  end

  class FGCZCluster < Cluster
    def submit_job(script_file, script_content, option='')
      if script_name = File.basename(script_file) and script_name =~ /\.sh$/
        new_job_script = generate_new_job_script(script_name, script_content)
        new_job_script_base = File.basename(new_job_script)
        log_file = File.join(@log_dir, new_job_script_base + "_o.log")
        err_file = File.join(@log_dir, new_job_script_base + "_e.log")
        command = "g-sub -o #{log_file} -e #{err_file} #{option} #{new_job_script}"
        job_id = `#{command}`
        job_id = job_id.match(/Your job (\d+) \(/)[1]
        [job_id, log_file, command]
      end
    end
    def job_running?(job_id)
     qstat_flag = false
      IO.popen('qstat -u "*"') do |io|
        while line=io.gets
          if line =~ /#{job_id}/
            qstat_flag = true
            break
          end
        end
      end
      qstat_flag
    end
    def job_ends?(log_file)
      log_flag = false
      IO.popen("tail -n 10 #{log_file} 2> /dev/null") do |io|
        while line=io.gets
          if line =~ /__SCRIPT END__/
            log_flag = true
            break
          end
        end
      end
      log_flag
    end
    def copy_commands(org_dir, dest_parent_dir, now=nil)
      commands = if now
                   ["g-req copynow #{org_dir} #{dest_parent_dir}"]
                 else
                   ["g-req -w copy #{org_dir} #{dest_parent_dir}"]
                 end
    end
    def kill_command(job_id)
      command = "qdel #{job_id}"
    end
    def delete_command(target)
      command = "g-req remove #{target}"
    end
  end

  class FGCZCourseCluster < FGCZCluster
    def copy_commands(org_dir, dest_parent_dir, now=nil)
      commands = ["cp -r #{org_dir} #{dest_parent_dir}"]
    end
    def delete_command(target)
      command = "rm -rf #{target}"
    end
  end
end
