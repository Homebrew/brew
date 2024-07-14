require_relative "whirly/version"
require_relative "whirly/spinners"

require "unicode/display_width"

begin
  require "paint"
rescue LoadError
end

module Whirly
  @configured = false

  CLI_COMMANDS = {
    hide_cursor: "\x1b[?25l",
    show_cursor: "\x1b[?25h",
  }.freeze

  DEFAULT_OPTIONS = {
    ambiguous_character_width: 1,
    ansi_escape_mode: "restore",
    append_newline: true,
    color: !!defined?(Paint),
    color_change_rate: 30,
    hide_cursor: true,
    non_tty: false,
    position: "normal",
    remove_after_stop: false,
    spinner: "whirly",
    spinner_packs: [:whirly, :cli],
    status: nil,
    stream: $stdout,
  }.freeze

  SOFT_DEFAULT_OPTIONS = {
    interval: 100,
    mode: "linear",
    stop: nil,
  }.freeze

  class << self
    attr_accessor :status
    attr_reader :options

    def enabled?
      !!(defined?(@enabled) && @enabled)
    end

    def configured?
      !!(@configured)
    end
  end

  # set spinner directly or lookup
  def self.configure_spinner(spinner_option)
    case spinner_option
    when Hash
      spinner = spinner_option.dup
    when Enumerable
      spinner = { "frames" => spinner_option.dup }
    when Proc
      spinner = { "proc" => spinner_option.dup }
    else
      spinner = nil
      catch(:found){
        @options[:spinner_packs].each{ |spinner_pack|
          spinners = Whirly::Spinners.const_get(spinner_pack.to_s.upcase)
          if spinners[spinner_option]
            spinner = spinners[spinner_option].dup
            throw(:found)
          end
        }
      }
    end

    # validate spinner
    if !spinner || (!spinner["frames"] && !spinner["proc"])
      raise(ArgumentError, "Whirly: Invalid spinner given")
    end

    spinner
  end

  # frames can be generated from enumerables or procs
  def self.configure_frames(spinner)
    if spinner["frames"]
      case spinner["mode"]
      when "swing"
        frames = (spinner["frames"].to_a + spinner["frames"].to_a[1..-2].reverse).cycle
      when "random"
        frame_pool = spinner["frames"].to_a
        frames = ->(){ frame_pool.sample }
      when "reverse"
        frames = spinner["frames"].to_a.reverse.cycle
      else
        frames = spinner["frames"].cycle
      end
    elsif spinner["proc"]
      frames = spinner["proc"].dup
    else
      raise(ArgumentError, "Whirly: Invalid spinner given")
    end

    if frames.is_a? Proc
      class << frames
        alias next call
      end
    end

    frames
  end

  # save options and preprocess, set defaults if value is still unknown
  def self.configure(**options)
    if !defined?(@configured) || !@configured || !defined?(@options) || !@options
      @options = DEFAULT_OPTIONS.dup
      @configured = true
    end

    @options.merge!(options)

    spinner = configure_spinner(@options[:spinner])
    spinner_overwrites = {}
    spinner_overwrites["mode"] = @options[:mode] if @options.key?(:mode)
    @frames   = configure_frames(spinner.merge(spinner_overwrites))

    @interval = (@options[:interval] || spinner["interval"] || SOFT_DEFAULT_OPTIONS[:interval]) * 0.001
    @stop     = @options[:stop] || spinner["stop"]
    @status   = @options[:status]
  end

  def self.start(**options)
    # optionally overwrite configuration on start
    configure(**options)

    # only enable once
    return false if defined?(@enabled) && @enabled

    # set status to enabled
    @enabled = true

    # only do something if we are on a real terminal (or forced)
    return false unless @options[:stream].tty? || @options[:non_tty]

    # ensure cursor is visible after exit the program (only register for the very first time)
    if (!defined?(@at_exit_handler_registered) || !@at_exit_handler_registered) && @options[:hide_cursor]
      @at_exit_handler_registered = true
      stream = @options[:stream]
      at_exit{ stream.print CLI_COMMANDS[:show_cursor] }
    end

    # init color
    initialize_color if @options[:color]

    # hide cursor
    @options[:stream].print CLI_COMMANDS[:hide_cursor] if @options[:hide_cursor]

    # start spinner loop
    @thread = Thread.new do
      @current_frame = nil
      while true # it's just a spinner, no exact timing here
        next_color if @color
        render
        sleep(@interval)
      end
    end

    # idiomatic block syntax support
    if block_given?
      begin
        yield
      ensure
        Whirly.stop
      end
    end

    true
  end

  def self.stop(stop_frame = nil)
    return false unless @enabled
    @enabled = false
    return false unless @options[:stream].tty? || @options[:non_tty]

    @thread.terminate if @thread
    render(stop_frame || @stop) if stop_frame || @stop
    unrender if @options[:remove_after_stop]
    @options[:stream].puts if @options[:append_newline]
    @options[:stream].print CLI_COMMANDS[:show_cursor] if @options[:hide_cursor]

    true
  end

  def self.reset
    at_exit_handler_registered = defined?(@at_exit_handler_registered) && @at_exit_handler_registered
    instance_variables.each{ |iv| remove_instance_variable(iv) }
    @at_exit_handler_registered = at_exit_handler_registered
    @configured = false
  end

  # - - -

  def self.unrender
    return unless @current_frame
    case @options[:ansi_escape_mode]
    when "restore"
      @options[:stream].print(render_prefix + (
          ' ' * (Unicode::DisplayWidth.of(@current_frame, @options[:ambiguous_character_width]) + 1)
      ) + render_suffix)
    when "line"
      @options[:stream].print "\e[1K"
    end
  end

  def self.render(next_frame = nil)
    unrender

    @current_frame = next_frame || @frames.next
    @current_frame = Paint[@current_frame, @color] if @options[:color]
    @current_frame += "  #{@status}" if @status

    @options[:stream].print(render_prefix + @current_frame.to_s + render_suffix)
  end

  def self.render_prefix
    res = ""
    res << "\n" if @options[:position] == "below"
    res << "\e7" if @options[:ansi_escape_mode] == "restore"
    res << "\e[G" if @options[:ansi_escape_mode] == "line"
    res
  end

  def self.render_suffix
    res = ""
    res << "\e8" if @options[:ansi_escape_mode] == "restore"
    res << "\e[1A" if @options[:position] == "below"
    res
  end

  def self.initialize_color
    if !defined?(Paint)
      warn "Whirly warning: Using colors requires the paint gem"
    else
      @color = "%.6x" % rand(16777216)
      @color_directions = (0..2).map{ |e| rand(3) - 1 }
    end
  end

  def self.next_color
    @color = @color.scan(/../).map.with_index{ |c, i|
      color_change = rand(@options[:color_change_rate]) * @color_directions[i]
      nc = c.to_i(16) + color_change
      if nc <= 0
        nc = 0
        @color_directions[i] = rand(3) - 1
      elsif nc >= 255
        nc = 255
        @color_directions[i] = rand(3) - 1
      end
      "%.2x" % nc
    }.join
  end
end
