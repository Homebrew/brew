# frozen_string_literal: true
#--
# benchmark.rb - a performance benchmarking library
#
# $Id$
#
# Created by Gotoken (gotoken@notwork.org).
#
# Documentation by Gotoken (original RD), Lyle Johnson (RDoc conversion), and
# Gavin Sinclair (editing).
#++
#
# == Overview
#
# The Benchmark module provides methods for benchmarking Ruby code, giving
# detailed reports on the time taken for each task.
#

# The Benchmark module provides methods to measure and report the time
# used to execute Ruby code.
#
# * Measure the time to construct the string given by the expression
#   <code>"a"*1_000_000_000</code>:
#
#       require 'benchmark'
#
#       puts Benchmark.measure { "a"*1_000_000_000 }
#
#   On my machine (OSX 10.8.3 on i5 1.7 GHz) this generates:
#
#       0.350000   0.400000   0.750000 (  0.835234)
#
#   This report shows the user CPU time, system CPU time, the sum of
#   the user and system CPU times, and the elapsed real time. The unit
#   of time is seconds.
#
# * Do some experiments sequentially using the #bm method:
#
#       require 'benchmark'
#
#       n = 5000000
#       Benchmark.bm do |x|
#         x.report { for i in 1..n; a = "1"; end }
#         x.report { n.times do   ; a = "1"; end }
#         x.report { 1.upto(n) do ; a = "1"; end }
#       end
#
#   The result:
#
#              user     system      total        real
#          1.010000   0.000000   1.010000 (  1.014479)
#          1.000000   0.000000   1.000000 (  0.998261)
#          0.980000   0.000000   0.980000 (  0.981335)
#
# * Continuing the previous example, put a label in each report:
#
#       require 'benchmark'
#
#       n = 5000000
#       Benchmark.bm(7) do |x|
#         x.report("for:")   { for i in 1..n; a = "1"; end }
#         x.report("times:") { n.times do   ; a = "1"; end }
#         x.report("upto:")  { 1.upto(n) do ; a = "1"; end }
#       end
#
# The result:
#
#                     user     system      total        real
#       for:      1.010000   0.000000   1.010000 (  1.015688)
#       times:    1.000000   0.000000   1.000000 (  1.003611)
#       upto:     1.030000   0.000000   1.030000 (  1.028098)
#
# * The times for some benchmarks depend on the order in which items
#   are run.  These differences are due to the cost of memory
#   allocation and garbage collection. To avoid these discrepancies,
#   the #bmbm method is provided.  For example, to compare ways to
#   sort an array of floats:
#
#       require 'benchmark'
#
#       array = (1..1000000).map { rand }
#
#       Benchmark.bmbm do |x|
#         x.report("sort!") { array.dup.sort! }
#         x.report("sort")  { array.dup.sort  }
#       end
#
#   The result:
#
#        Rehearsal -----------------------------------------
#        sort!   1.490000   0.010000   1.500000 (  1.490520)
#        sort    1.460000   0.000000   1.460000 (  1.463025)
#        -------------------------------- total: 2.960000sec
#
#                    user     system      total        real
#        sort!   1.460000   0.000000   1.460000 (  1.460465)
#        sort    1.450000   0.010000   1.460000 (  1.448327)
#
# * Report statistics of sequential experiments with unique labels,
#   using the #benchmark method:
#
#       require 'benchmark'
#       include Benchmark         # we need the CAPTION and FORMAT constants
#
#       n = 5000000
#       Benchmark.benchmark(CAPTION, 7, FORMAT, ">total:", ">avg:") do |x|
#         tf = x.report("for:")   { for i in 1..n; a = "1"; end }
#         tt = x.report("times:") { n.times do   ; a = "1"; end }
#         tu = x.report("upto:")  { 1.upto(n) do ; a = "1"; end }
#         [tf+tt+tu, (tf+tt+tu)/3]
#       end
#
#   The result:
#
#                     user     system      total        real
#        for:      0.950000   0.000000   0.950000 (  0.952039)
#        times:    0.980000   0.000000   0.980000 (  0.984938)
#        upto:     0.950000   0.000000   0.950000 (  0.946787)
#        >total:   2.880000   0.000000   2.880000 (  2.883764)
#        >avg:     0.960000   0.000000   0.960000 (  0.961255)

module Benchmark

  VERSION = "0.3.0"

  BENCHMARK_VERSION = "2002-04-25" # :nodoc:

  # Invokes the block with a Benchmark::Report object, which
  # may be used to collect and report on the results of individual
  # benchmark tests. Reserves +label_width+ leading spaces for
  # labels on each line. Prints +caption+ at the top of the
  # report, and uses +format+ to format each line.
  # (Note: +caption+ must contain a terminating newline character,
  # see the default Benchmark::Tms::CAPTION for an example.)
  #
  # Returns an array of Benchmark::Tms objects.
  #
  # If the block returns an array of
  # Benchmark::Tms objects, these will be used to format
  # additional lines of output. If +labels+ parameter are
  # given, these are used to label these extra lines.
  #
  # _Note_: Other methods provide a simpler interface to this one, and are
  # suitable for nearly all benchmarking requirements.  See the examples in
  # Benchmark, and the #bm and #bmbm methods.
  #
  # Example:
  #
  #     require 'benchmark'
  #     include Benchmark          # we need the CAPTION and FORMAT constants
  #
  #     n = 5000000
  #     Benchmark.benchmark(CAPTION, 7, FORMAT, ">total:", ">avg:") do |x|
  #       tf = x.report("for:")   { for i in 1..n; a = "1"; end }
  #       tt = x.report("times:") { n.times do   ; a = "1"; end }
  #       tu = x.report("upto:")  { 1.upto(n) do ; a = "1"; end }
  #       [tf+tt+tu, (tf+tt+tu)/3]
  #     end
  #
  # Generates:
  #
  #                     user     system      total        real
  #       for:      0.970000   0.000000   0.970000 (  0.970493)
  #       times:    0.990000   0.000000   0.990000 (  0.989542)
  #       upto:     0.970000   0.000000   0.970000 (  0.972854)
  #       >total:   2.930000   0.000000   2.930000 (  2.932889)
  #       >avg:     0.976667   0.000000   0.976667 (  0.977630)
  #

  def benchmark(caption = "", label_width = nil, format = nil, *labels) # :yield: report
    sync = $stdout.sync
    $stdout.sync = true
    label_width ||= 0
    label_width += 1
    format ||= FORMAT
    print ' '*label_width + caption unless caption.empty?
    report = Report.new(label_width, format)
    results = yield(report)
    Array === results and results.grep(Tms).each {|t|
      print((labels.shift || t.label || "").ljust(label_width), t.format(format))
    }
    report.list
  ensure
    $stdout.sync = sync unless sync.nil?
  end


  # A simple interface to the #benchmark method, #bm generates sequential
  # reports with labels. +label_width+ and +labels+ parameters have the same
  # meaning as for #benchmark.
  #
  #     require 'benchmark'
  #
  #     n = 5000000
  #     Benchmark.bm(7) do |x|
  #       x.report("for:")   { for i in 1..n; a = "1"; end }
  #       x.report("times:") { n.times do   ; a = "1"; end }
  #       x.report("upto:")  { 1.upto(n) do ; a = "1"; end }
  #     end
  #
  # Generates:
  #
  #                     user     system      total        real
  #       for:      0.960000   0.000000   0.960000 (  0.957966)
  #       times:    0.960000   0.000000   0.960000 (  0.960423)
  #       upto:     0.950000   0.000000   0.950000 (  0.954864)
  #

  def bm(label_width = 0, *labels, &blk) # :yield: report
    benchmark(CAPTION, label_width, FORMAT, *labels, &blk)
  end


  # Sometimes benchmark results are skewed because code executed
  # earlier encounters different garbage collection overheads than
  # that run later. #bmbm attempts to minimize this effect by running
  # the tests twice, the first time as a rehearsal in order to get the
  # runtime environment stable, the second time for
  # real. GC.start is executed before the start of each of
  # the real timings; the cost of this is not included in the
  # timings. In reality, though, there's only so much that #bmbm can
  # do, and the results are not guaranteed to be isolated from garbage
  # collection and other effects.
  #
  # Because #bmbm takes two passes through the tests, it can
  # calculate the required label width.
  #
  #       require 'benchmark'
  #
  #       array = (1..1000000).map { rand }
  #
  #       Benchmark.bmbm do |x|
  #         x.report("sort!") { array.dup.sort! }
  #         x.report("sort")  { array.dup.sort  }
  #       end
  #
  # Generates:
  #
  #        Rehearsal -----------------------------------------
  #        sort!   1.440000   0.010000   1.450000 (  1.446833)
  #        sort    1.440000   0.000000   1.440000 (  1.448257)
  #        -------------------------------- total: 2.890000sec
  #
  #                    user     system      total        real
  #        sort!   1.460000   0.000000   1.460000 (  1.458065)
  #        sort    1.450000   0.000000   1.450000 (  1.455963)
  #
  # #bmbm yields a Benchmark::Job object and returns an array of
  # Benchmark::Tms objects.
  #
  def bmbm(width = 0) # :yield: job
    job = Job.new(width)
    yield(job)
    width = job.width + 1
    sync = $stdout.sync
    $stdout.sync = true

    # rehearsal
    puts 'Rehearsal '.ljust(width+CAPTION.length,'-')
    ets = job.list.inject(Tms.new) { |sum,(label,item)|
      print label.ljust(width)
      res = Benchmark.measure(&item)
      print res.format
      sum + res
    }.format("total: %tsec")
    print " #{ets}\n\n".rjust(width+CAPTION.length+2,'-')

    # take
    print ' '*width + CAPTION
    job.list.map { |label,item|
      GC.start
      print label.ljust(width)
      Benchmark.measure(label, &item).tap { |res| print res }
    }
  ensure
    $stdout.sync = sync unless sync.nil?
  end

  #
  # Returns the time used to execute the given block as a
  # Benchmark::Tms object. Takes +label+ option.
  #
  #       require 'benchmark'
  #
  #       n = 1000000
  #
  #       time = Benchmark.measure do
  #         n.times { a = "1" }
  #       end
  #       puts time
  #
  # Generates:
  #
  #        0.220000   0.000000   0.220000 (  0.227313)
  #
  def measure(label = "") # :yield:
    t0, r0 = Process.times, Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    t1, r1 = Process.times, Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Benchmark::Tms.new(t1.utime  - t0.utime,
                       t1.stime  - t0.stime,
                       t1.cutime - t0.cutime,
                       t1.cstime - t0.cstime,
                       r1 - r0,
                       label)
  end

  #
  # Returns the elapsed real time used to execute the given block.
  #
  def realtime # :yield:
    r0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - r0
  end

  module_function :benchmark, :measure, :realtime, :bm, :bmbm

  #
  # A Job is a sequence of labelled blocks to be processed by the
  # Benchmark.bmbm method.  It is of little direct interest to the user.
  #
  class Job # :nodoc:
    #
    # Returns an initialized Job instance.
    # Usually, one doesn't call this method directly, as new
    # Job objects are created by the #bmbm method.
    # +width+ is a initial value for the label offset used in formatting;
    # the #bmbm method passes its +width+ argument to this constructor.
    #
    def initialize(width)
      @width = width
      @list = []
    end

    #
    # Registers the given label and block pair in the job list.
    #
    def item(label = "", &blk) # :yield:
      raise ArgumentError, "no block" unless block_given?
      label = label.to_s
      w = label.length
      @width = w if @width < w
      @list << [label, blk]
      self
    end

    alias report item

    # An array of 2-element arrays, consisting of label and block pairs.
    attr_reader :list

    # Length of the widest label in the #list.
    attr_reader :width
  end

  #
  # This class is used by the Benchmark.benchmark and Benchmark.bm methods.
  # It is of little direct interest to the user.
  #
  class Report # :nodoc:
    #
    # Returns an initialized Report instance.
    # Usually, one doesn't call this method directly, as new
    # Report objects are created by the #benchmark and #bm methods.
    # +width+ and +format+ are the label offset and
    # format string used by Tms#format.
    #
    def initialize(width = 0, format = nil)
      @width, @format, @list = width, format, []
    end

    #
    # Prints the +label+ and measured time for the block,
    # formatted by +format+. See Tms#format for the
    # formatting rules.
    #
    def item(label = "", *format, &blk) # :yield:
      print label.to_s.ljust(@width)
      @list << res = Benchmark.measure(label, &blk)
      print res.format(@format, *format)
      res
    end

    alias report item

    # An array of Benchmark::Tms objects representing each item.
    attr_reader :list
  end



  #
  # A data object, representing the times associated with a benchmark
  # measurement.
  #
  class Tms

    # Default caption, see also Benchmark::CAPTION
    CAPTION = "      user     system      total        real\n"

    # Default format string, see also Benchmark::FORMAT
    FORMAT = "%10.6u %10.6y %10.6t %10.6r\n"

    # User CPU time
    attr_reader :utime

    # System CPU time
    attr_reader :stime

    # User CPU time of children
    attr_reader :cutime

    # System CPU time of children
    attr_reader :cstime

    # Elapsed real time
    attr_reader :real

    # Total time, that is +utime+ + +stime+ + +cutime+ + +cstime+
    attr_reader :total

    # Label
    attr_reader :label

    #
    # Returns an initialized Tms object which has
    # +utime+ as the user CPU time, +stime+ as the system CPU time,
    # +cutime+ as the children's user CPU time, +cstime+ as the children's
    # system CPU time, +real+ as the elapsed real time and +label+ as the label.
    #
    def initialize(utime = 0.0, stime = 0.0, cutime = 0.0, cstime = 0.0, real = 0.0, label = nil)
      @utime, @stime, @cutime, @cstime, @real, @label = utime, stime, cutime, cstime, real, label.to_s
      @total = @utime + @stime + @cutime + @cstime
    end

    #
    # Returns a new Tms object whose times are the sum of the times for this
    # Tms object, plus the time required to execute the code block (+blk+).
    #
    def add(&blk) # :yield:
      self + Benchmark.measure(&blk)
    end

    #
    # An in-place version of #add.
    # Changes the times of this Tms object by making it the sum of the times
    # for this Tms object, plus the time required to execute
    # the code block (+blk+).
    #
    def add!(&blk)
      t = Benchmark.measure(&blk)
      @utime  = utime + t.utime
      @stime  = stime + t.stime
      @cutime = cutime + t.cutime
      @cstime = cstime + t.cstime
      @real   = real + t.real
      self
    end

    #
    # Returns a new Tms object obtained by memberwise summation
    # of the individual times for this Tms object with those of the +other+
    # Tms object.
    # This method and #/() are useful for taking statistics.
    #
    def +(other); memberwise(:+, other) end

    #
    # Returns a new Tms object obtained by memberwise subtraction
    # of the individual times for the +other+ Tms object from those of this
    # Tms object.
    #
    def -(other); memberwise(:-, other) end

    #
    # Returns a new Tms object obtained by memberwise multiplication
    # of the individual times for this Tms object by +x+.
    #
    def *(x); memberwise(:*, x) end

    #
    # Returns a new Tms object obtained by memberwise division
    # of the individual times for this Tms object by +x+.
    # This method and #+() are useful for taking statistics.
    #
    def /(x); memberwise(:/, x) end

    #
    # Returns the contents of this Tms object as
    # a formatted string, according to a +format+ string
    # like that passed to Kernel.format. In addition, #format
    # accepts the following extensions:
    #
    # <tt>%u</tt>::     Replaced by the user CPU time, as reported by Tms#utime.
    # <tt>%y</tt>::     Replaced by the system CPU time, as reported by #stime (Mnemonic: y of "s*y*stem")
    # <tt>%U</tt>::     Replaced by the children's user CPU time, as reported by Tms#cutime
    # <tt>%Y</tt>::     Replaced by the children's system CPU time, as reported by Tms#cstime
    # <tt>%t</tt>::     Replaced by the total CPU time, as reported by Tms#total
    # <tt>%r</tt>::     Replaced by the elapsed real time, as reported by Tms#real
    # <tt>%n</tt>::     Replaced by the label string, as reported by Tms#label (Mnemonic: n of "*n*ame")
    #
    # If +format+ is not given, FORMAT is used as default value, detailing the
    # user, system and real elapsed time.
    #
    def format(format = nil, *args)
      str = (format || FORMAT).dup
      str.gsub!(/(%[-+.\d]*)n/) { "#{$1}s" % label }
      str.gsub!(/(%[-+.\d]*)u/) { "#{$1}f" % utime }
      str.gsub!(/(%[-+.\d]*)y/) { "#{$1}f" % stime }
      str.gsub!(/(%[-+.\d]*)U/) { "#{$1}f" % cutime }
      str.gsub!(/(%[-+.\d]*)Y/) { "#{$1}f" % cstime }
      str.gsub!(/(%[-+.\d]*)t/) { "#{$1}f" % total }
      str.gsub!(/(%[-+.\d]*)r/) { "(#{$1}f)" % real }
      format ? str % args : str
    end

    #
    # Same as #format.
    #
    def to_s
      format
    end

    #
    # Returns a new 6-element array, consisting of the
    # label, user CPU time, system CPU time, children's
    # user CPU time, children's system CPU time and elapsed
    # real time.
    #
    def to_a
      [@label, @utime, @stime, @cutime, @cstime, @real]
    end

    #
    # Returns a hash containing the same data as `to_a`.
    #
    def to_h
      {
        label:  @label,
        utime:  @utime,
        stime:  @stime,
        cutime: @cutime,
        cstime: @cstime,
        real:   @real
      }
    end

    protected

    #
    # Returns a new Tms object obtained by memberwise operation +op+
    # of the individual times for this Tms object with those of the other
    # Tms object (+x+).
    #
    # +op+ can be a mathematical operation such as <tt>+</tt>, <tt>-</tt>,
    # <tt>*</tt>, <tt>/</tt>
    #
    def memberwise(op, x)
      case x
      when Benchmark::Tms
        Benchmark::Tms.new(utime.__send__(op, x.utime),
                           stime.__send__(op, x.stime),
                           cutime.__send__(op, x.cutime),
                           cstime.__send__(op, x.cstime),
                           real.__send__(op, x.real)
                           )
      else
        Benchmark::Tms.new(utime.__send__(op, x),
                           stime.__send__(op, x),
                           cutime.__send__(op, x),
                           cstime.__send__(op, x),
                           real.__send__(op, x)
                           )
      end
    end
  end

  # The default caption string (heading above the output times).
  CAPTION = Benchmark::Tms::CAPTION

  # The default format string used to display times.  See also Benchmark::Tms#format.
  FORMAT = Benchmark::Tms::FORMAT
end
