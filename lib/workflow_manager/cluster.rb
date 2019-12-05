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
      new_job_script = File.basename(script_name) + "_" + Time.now.strftime("%Y%m%d%H%M%S%L")
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
    def job_pending?(job_id)
    end
    def copy_commands(org_dir, dest_parent_dir, now=nil)
    end
    def kill_command(job_id)
    end
    def delete_command(target)
    end
    def cluster_nodes
    end
    def default_node
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
    def cluster_nodes
      {"Local Computer" => ""}
    end
  end

  class TaskSpooler < LocalComputer
    def submit_job(script_file, script_content, option='')
      if script_name = File.basename(script_file) and script_name =~ /\.sh$/
        new_job_script = generate_new_job_script(script_name, script_content)
        new_job_script_base = File.basename(new_job_script)
        log_file = File.join(@log_dir, new_job_script_base + "_o.log")
        err_file = File.join(@log_dir, new_job_script_base + "_e.log")
        command = "tsp sh -c 'bash #{new_job_script} 1> #{log_file} 2> #{err_file}'"
        job_id = `#{command}`.to_s.chomp
        [job_id.to_s, log_file, command]
      end
    end
    def job_running?(pid)
      command = "tsp"
      result = IO.popen(command) do |io|
        flag = false
        while line=io.gets
          x = line.split
          if x[0].to_i == pid.to_i and x[1] == "running"
            flag = true
            break
          end
        end
        flag
      end
      result
    end
    def kill_command(job_id)
      command = "tsp -k #{job_id}"
    end
    def cluster_nodes
      {"Local with TaskSpooler" => ""}
    end
  end

  class FGCZCluster < Cluster
    def submit_job(script_file, script_content, option='')
      if script_name = File.basename(script_file) and script_name =~ /\.sh/
        script_name = script_name.split(/\.sh/).first + ".sh"
        new_job_script = generate_new_job_script(script_name, script_content)
        new_job_script_base = File.basename(new_job_script)
        log_file = File.join(@log_dir, new_job_script_base + "_o.log")
        err_file = File.join(@log_dir, new_job_script_base + "_e.log")
        command = "g-sub -o #{log_file} -e #{err_file} #{option} #{new_job_script}"
        job_id = `#{command}`
        job_id = job_id.match(/Your job (\d+) \(/)[1]
        [job_id, log_file, command]
      else
        err_msg = "FGCZCluster#submit_job, ERROR: script_name is not *.sh: #{File.basename(script_file)}"
        warn err_msg
        raise err_msg
      end
    end
    def job_running?(job_id)
     qstat_flag = false
      IO.popen('qstat -u "*"') do |io|
        while line=io.gets
          jobid, prior, name, user, state, *others = line.chomp.split
          if jobid.strip == job_id and state == 'r'
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
    def job_pending?(job_id)
     qstat_flag = false
      IO.popen('qstat -u "*"') do |io|
        while line=io.gets
          jobid, prior, name, user, state, *others = line.chomp.split
          if jobid.strip == job_id and state =~ /qw/
            qstat_flag = true
            break
          end
        end
      end
      qstat_flag
    end
    def copy_commands(org_dir, dest_parent_dir, now=nil)
      commands = if now == "force"
                   target_file = File.join(dest_parent_dir, File.basename(org_dir))
                   ["g-req copynow -f #{org_dir} #{dest_parent_dir}"]
                 elsif now
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
    def cluster_nodes
      nodes = {
        'fgcz-c-043: cpu 24,mem  23 GB,scr  11T' => 'fgcz-c-043',
        'fgcz-c-044: cpu 16,mem 128 GB,scr 500G' => 'fgcz-c-044',
        'fgcz-c-045: cpu 64,mem 504 GB,scr  15T' => 'fgcz-c-045',
        'fgcz-c-046: cpu 64,mem 504 GB,scr  11T' => 'fgcz-c-046',
        'fgcz-c-047: cpu 32,mem   1 TB,scr  28T' => 'fgcz-c-047',
        'fgcz-c-048: cpu 48,mem 252 GB,scr 3.5T' => 'fgcz-c-048',
        'fgcz-c-049: cpu  8,mem  63 GB,scr 1.7T' => 'fgcz-c-049',
        'fgcz-c-051: cpu  8,mem  31 GB,scr 800G' => 'fgcz-c-051',
        'fgcz-c-052: cpu  8,mem  31 GB,scr 800G' => 'fgcz-c-052',
        'fgcz-c-053: cpu  8,mem  31 GB,scr 800G' => 'fgcz-c-053',
        'fgcz-c-054: cpu  8,mem  31 GB,scr 800G' => 'fgcz-c-054',
        'fgcz-c-055: cpu  8,mem  31 GB,scr 800G' => 'fgcz-c-055',
        'fgcz-c-057: cpu  8,mem  31 GB,scr 200G' => 'fgcz-c-057',
        'fgcz-c-058: cpu  8,mem  31 GB,scr 200G' => 'fgcz-c-058',
        'fgcz-c-059: cpu  8,mem  31 GB,scr 200G' => 'fgcz-c-059',
        'fgcz-c-061: cpu  8,mem  31 GB,scr 200G' => 'fgcz-c-061',
        'fgcz-c-063: cpu 12,mem  70 GB,scr 450G' => 'fgcz-c-063',
        'fgcz-c-065: cpu 24,mem  70 GB,scr 197G' => 'fgcz-c-065',
        'fgcz-h-004: cpu 8,mem  30 GB,scr 400G' => 'fgcz-h-004',
        'fgcz-h-009: cpu 8,mem  30 GB,scr 500G' => 'fgcz-h-009',
        'fgcz-h-010: cpu 8,mem  30 GB,scr 400G' => 'fgcz-h-010',
      }
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

  class HydraCluster < Cluster
    def submit_job(script_file, script_content, option='')
      # TODO
      if script_name = File.basename(script_file) and script_name =~ /\.sh$/
        new_job_script = generate_new_job_script(script_name, script_content)
        new_job_script_base = File.basename(new_job_script)
        log_file = File.join(@log_dir, new_job_script_base + "_o.log")
        err_file = File.join(@log_dir, new_job_script_base + "_e.log")
        #command = "g-sub -o #{log_file} -e #{err_file} #{option} #{new_job_script}"
        command = "cat #{new_job_script} |ssh hydra 'cat > #{new_job_script_base}; source /etc/profile; module load cluster/largemem; sbatch #{new_job_script_base};'"
        job_id = `#{command}`
        job_id = job_id.match(/Submitted batch job (\d+)/)[1]
        [job_id, log_file, command]
      end
    end
    def job_running?(job_id)
      # TODO
    end
    def job_ends?(log_file)
      # TODO
    end
    def job_pending?(job_id)
      # TODO
    end
    def copy_commands(org_dir, dest_parent_dir, now=nil)
      # TODO
    end
    def kill_command(job_id)
      # TODO
      command = "ssh hydra; scancel #{job_id}"
    end
    def delete_command(target)
      # TODO
    end
    def cluster_nodes
      # TODO
      nodes = {
        'cluster/largemem' => 'cluster/largemem',
      }
    end
  end
end
