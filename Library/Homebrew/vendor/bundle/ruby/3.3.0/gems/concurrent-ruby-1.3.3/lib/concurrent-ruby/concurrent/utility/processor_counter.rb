require 'etc'
require 'rbconfig'
require 'concurrent/delay'

module Concurrent
  # @!visibility private
  module Utility

    # @!visibility private
    class ProcessorCounter
      def initialize
        @processor_count          = Delay.new { compute_processor_count }
        @physical_processor_count = Delay.new { compute_physical_processor_count }
        @cpu_quota                = Delay.new { compute_cpu_quota }
      end

      def processor_count
        @processor_count.value
      end

      def physical_processor_count
        @physical_processor_count.value
      end

      def available_processor_count
        cpu_count = processor_count.to_f
        quota = cpu_quota

        return cpu_count if quota.nil?

        # cgroup cpus quotas have no limits, so they can be set to higher than the
        # real count of cores.
        if quota > cpu_count
          cpu_count
        else
          quota
        end
      end

      def cpu_quota
        @cpu_quota.value
      end

      private

      def compute_processor_count
        if Concurrent.on_jruby?
          java.lang.Runtime.getRuntime.availableProcessors
        else
          Etc.nprocessors
        end
      end

      def compute_physical_processor_count
        ppc = case RbConfig::CONFIG["target_os"]
              when /darwin\d\d/
                IO.popen("/usr/sbin/sysctl -n hw.physicalcpu", &:read).to_i
              when /linux/
                cores = {} # unique physical ID / core ID combinations
                phy   = 0
                IO.read("/proc/cpuinfo").scan(/^physical id.*|^core id.*/) do |ln|
                  if ln.start_with?("physical")
                    phy = ln[/\d+/]
                  elsif ln.start_with?("core")
                    cid        = phy + ":" + ln[/\d+/]
                    cores[cid] = true if not cores[cid]
                  end
                end
                cores.count
              when /mswin|mingw/
                # Get-CimInstance introduced in PowerShell 3 or earlier: https://learn.microsoft.com/en-us/previous-versions/powershell/module/cimcmdlets/get-ciminstance?view=powershell-3.0
                result = run('powershell -command "Get-CimInstance -ClassName Win32_Processor -Property NumberOfCores | Select-Object -Property NumberOfCores"')
                if !result || $?.exitstatus != 0
                  # fallback to deprecated wmic for older systems
                  result = run("wmic cpu get NumberOfCores")
                end
                if !result || $?.exitstatus != 0
                  # Bail out if both commands returned something unexpected
                  processor_count
                else
                  # powershell: "\nNumberOfCores\n-------------\n            4\n\n\n" 
                  # wmic:       "NumberOfCores  \n\n4              \n\n\n\n"
                  result.scan(/\d+/).map(&:to_i).reduce(:+)
                end
              else
                processor_count
              end
        # fall back to logical count if physical info is invalid
        ppc > 0 ? ppc : processor_count
      rescue
        return 1
      end

      def run(command)
        IO.popen(command, &:read)
      rescue Errno::ENOENT
      end

      def compute_cpu_quota
        if RbConfig::CONFIG["target_os"].include?("linux")
          if File.exist?("/sys/fs/cgroup/cpu.max")
            # cgroups v2: https://docs.kernel.org/admin-guide/cgroup-v2.html#cpu-interface-files
            cpu_max = File.read("/sys/fs/cgroup/cpu.max")
            return nil if cpu_max.start_with?("max ") # no limit
            max, period = cpu_max.split.map(&:to_f)
            max / period
          elsif File.exist?("/sys/fs/cgroup/cpu,cpuacct/cpu.cfs_quota_us")
            # cgroups v1: https://kernel.googlesource.com/pub/scm/linux/kernel/git/glommer/memcg/+/cpu_stat/Documentation/cgroups/cpu.txt
            max = File.read("/sys/fs/cgroup/cpu,cpuacct/cpu.cfs_quota_us").to_i
            return nil if max == 0
            period = File.read("/sys/fs/cgroup/cpu,cpuacct/cpu.cfs_period_us").to_f
            max / period
          end
        end
      end
    end
  end

  # create the default ProcessorCounter on load
  @processor_counter = Utility::ProcessorCounter.new
  singleton_class.send :attr_reader, :processor_counter

  # Number of processors seen by the OS and used for process scheduling. For
  # performance reasons the calculated value will be memoized on the first
  # call.
  #
  # When running under JRuby the Java runtime call
  # `java.lang.Runtime.getRuntime.availableProcessors` will be used. According
  # to the Java documentation this "value may change during a particular
  # invocation of the virtual machine... [applications] should therefore
  # occasionally poll this property." Subsequently the result will NOT be
  # memoized under JRuby.
  #
  # Otherwise Ruby's Etc.nprocessors will be used.
  #
  # @return [Integer] number of processors seen by the OS or Java runtime
  #
  # @see http://docs.oracle.com/javase/6/docs/api/java/lang/Runtime.html#availableProcessors()
  def self.processor_count
    processor_counter.processor_count
  end

  # Number of physical processor cores on the current system. For performance
  # reasons the calculated value will be memoized on the first call.
  #
  # On Windows the Win32 API will be queried for the `NumberOfCores from
  # Win32_Processor`. This will return the total number "of cores for the
  # current instance of the processor." On Unix-like operating systems either
  # the `hwprefs` or `sysctl` utility will be called in a subshell and the
  # returned value will be used. In the rare case where none of these methods
  # work or an exception is raised the function will simply return 1.
  #
  # @return [Integer] number physical processor cores on the current system
  #
  # @see https://github.com/grosser/parallel/blob/4fc8b89d08c7091fe0419ca8fba1ec3ce5a8d185/lib/parallel.rb
  #
  # @see http://msdn.microsoft.com/en-us/library/aa394373(v=vs.85).aspx
  # @see http://www.unix.com/man-page/osx/1/HWPREFS/
  # @see http://linux.die.net/man/8/sysctl
  def self.physical_processor_count
    processor_counter.physical_processor_count
  end

  # Number of processors cores available for process scheduling.
  # Returns `nil` if there is no #cpu_quota, or a `Float` if the
  # process is inside a cgroup with a dedicated CPU quota (typically Docker).
  #
  # For performance reasons the calculated value will be memoized on the first
  # call.
  #
  # @return [nil, Float] number of available processors
  def self.available_processor_count
    processor_counter.available_processor_count
  end

  # The maximum number of processors cores available for process scheduling.
  # Returns `nil` if there is no enforced limit, or a `Float` if the
  # process is inside a cgroup with a dedicated CPU quota (typically Docker).
  #
  # Note that nothing prevents setting a CPU quota higher than the actual number of
  # cores on the system.
  #
  # For performance reasons the calculated value will be memoized on the first
  # call.
  #
  # @return [nil, Float] Maximum number of available processors as set by a cgroup CPU quota, or nil if none set
  def self.cpu_quota
    processor_counter.cpu_quota
  end
end
