# frozen_string_literal: false
#
#   irb/multi-irb.rb - multiple irb module
#   	$Release Version: 0.9.6$
#   	$Revision$
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#
# --
#
#
#
fail CantShiftToMultiIrbMode unless defined?(Thread)

module IRB
  class JobManager

    # Creates a new JobManager object
    def initialize
      @jobs = []
      @current_job = nil
    end

    # The active irb session
    attr_accessor :current_job

    # The total number of irb sessions, used to set +irb_name+ of the current
    # Context.
    def n_jobs
      @jobs.size
    end

    # Returns the thread for the given +key+ object, see #search for more
    # information.
    def thread(key)
      th, = search(key)
      th
    end

    # Returns the irb session for the given +key+ object, see #search for more
    # information.
    def irb(key)
      _, irb = search(key)
      irb
    end

    # Returns the top level thread.
    def main_thread
      @jobs[0][0]
    end

    # Returns the top level irb session.
    def main_irb
      @jobs[0][1]
    end

    # Add the given +irb+ session to the jobs Array.
    def insert(irb)
      @jobs.push [Thread.current, irb]
    end

    # Changes the current active irb session to the given +key+ in the jobs
    # Array.
    #
    # Raises an IrbAlreadyDead exception if the given +key+ is no longer alive.
    #
    # If the given irb session is already active, an IrbSwitchedToCurrentThread
    # exception is raised.
    def switch(key)
      th, irb = search(key)
      fail IrbAlreadyDead unless th.alive?
      fail IrbSwitchedToCurrentThread if th == Thread.current
      @current_job = irb
      th.run
      Thread.stop
      @current_job = irb(Thread.current)
    end

    # Terminates the irb sessions specified by the given +keys+.
    #
    # Raises an IrbAlreadyDead exception if one of the given +keys+ is already
    # terminated.
    #
    # See Thread#exit for more information.
    def kill(*keys)
      for key in keys
        th, _ = search(key)
        fail IrbAlreadyDead unless th.alive?
        th.exit
      end
    end

    # Returns the associated job for the given +key+.
    #
    # If given an Integer, it will return the +key+ index for the jobs Array.
    #
    # When an instance of Irb is given, it will return the irb session
    # associated with +key+.
    #
    # If given an instance of Thread, it will return the associated thread
    # +key+ using Object#=== on the jobs Array.
    #
    # Otherwise returns the irb session with the same top-level binding as the
    # given +key+.
    #
    # Raises a NoSuchJob exception if no job can be found with the given +key+.
    def search(key)
      job = case key
            when Integer
              @jobs[key]
            when Irb
              @jobs.find{|k, v| v.equal?(key)}
            when Thread
              @jobs.assoc(key)
            else
              @jobs.find{|k, v| v.context.main.equal?(key)}
            end
      fail NoSuchJob, key if job.nil?
      job
    end

    # Deletes the job at the given +key+.
    def delete(key)
      case key
      when Integer
        fail NoSuchJob, key unless @jobs[key]
        @jobs[key] = nil
      else
        catch(:EXISTS) do
          @jobs.each_index do
            |i|
            if @jobs[i] and (@jobs[i][0] == key ||
                @jobs[i][1] == key ||
                @jobs[i][1].context.main.equal?(key))
              @jobs[i] = nil
              throw :EXISTS
            end
          end
          fail NoSuchJob, key
        end
      end
      until assoc = @jobs.pop; end unless @jobs.empty?
      @jobs.push assoc
    end

    # Outputs a list of jobs, see the irb command +irb_jobs+, or +jobs+.
    def inspect
      ary = []
      @jobs.each_index do
        |i|
        th, irb = @jobs[i]
        next if th.nil?

        if th.alive?
          if th.stop?
            t_status = "stop"
          else
            t_status = "running"
          end
        else
          t_status = "exited"
        end
        ary.push format("#%d->%s on %s (%s: %s)",
          i,
          irb.context.irb_name,
          irb.context.main,
          th,
          t_status)
      end
      ary.join("\n")
    end
  end

  @JobManager = JobManager.new

  # The current JobManager in the session
  def IRB.JobManager
    @JobManager
  end

  # The current Context in this session
  def IRB.CurrentContext
    IRB.JobManager.irb(Thread.current).context
  end

  # Creates a new IRB session, see Irb.new.
  #
  # The optional +file+ argument is given to Context.new, along with the
  # workspace created with the remaining arguments, see WorkSpace.new
  def IRB.irb(file = nil, *main)
    workspace = WorkSpace.new(*main)
    parent_thread = Thread.current
    Thread.start do
      begin
        irb = Irb.new(workspace, file)
      rescue
        print "Subirb can't start with context(self): ", workspace.main.inspect, "\n"
        print "return to main irb\n"
        Thread.pass
        Thread.main.wakeup
        Thread.exit
      end
      @CONF[:IRB_RC].call(irb.context) if @CONF[:IRB_RC]
      @JobManager.insert(irb)
      @JobManager.current_job = irb
      begin
        system_exit = false
        catch(:IRB_EXIT) do
          irb.eval_input
        end
      rescue SystemExit
        system_exit = true
        raise
        #fail
      ensure
        unless system_exit
          @JobManager.delete(irb)
          if @JobManager.current_job == irb
            if parent_thread.alive?
              @JobManager.current_job = @JobManager.irb(parent_thread)
              parent_thread.run
            else
              @JobManager.current_job = @JobManager.main_irb
              @JobManager.main_thread.run
            end
          end
        end
      end
    end
    Thread.stop
    @JobManager.current_job = @JobManager.irb(Thread.current)
  end

  @CONF[:SINGLE_IRB_MODE] = false
  @JobManager.insert(@CONF[:MAIN_CONTEXT].irb)
  @JobManager.current_job = @CONF[:MAIN_CONTEXT].irb

  class Irb
    def signal_handle
      unless @context.ignore_sigint?
        print "\nabort!!\n" if @context.verbose?
        exit
      end

      case @signal_status
      when :IN_INPUT
        print "^C\n"
        IRB.JobManager.thread(self).raise RubyLex::TerminateLineInput
      when :IN_EVAL
        IRB.irb_abort(self)
      when :IN_LOAD
        IRB.irb_abort(self, LoadAbort)
      when :IN_IRB
        # ignore
      else
        # ignore other cases as well
      end
    end
  end

  trap("SIGINT") do
    @JobManager.current_job.signal_handle
    Thread.stop
  end

end
