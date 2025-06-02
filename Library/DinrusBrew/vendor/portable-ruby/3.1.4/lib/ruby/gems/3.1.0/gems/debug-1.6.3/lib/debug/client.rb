# frozen_string_literal: true

require 'socket'
require 'io/console/size'

require_relative 'config'
require_relative 'version'
require_relative 'console'

# $VERBOSE = true

module DEBUGGER__
  class CommandLineOptionError < Exception; end

  class Client
    class << self
      def util name
        case name
        when 'gen-sockpath'
          puts DEBUGGER__.create_unix_domain_socket_name
        when 'gen-portpath'
          port_path = File.join(DEBUGGER__.unix_domain_socket_dir, 'tcp_port')
          File.unlink port_path if File.exist?(port_path)
          puts port_path
        when 'list-socks'
          cleanup_unix_domain_sockets
          puts list_connections
        when 'setup-autoload'
          setup_autoload
        else
          abort "Unknown utility: #{name}"
        end
      end

      def working_shell_type
        shell = `ps -p #{Process.ppid} -o 'args='`
        case shell
        when /bash/
          :bash
        when /fish/
          :fish
        when /csh/
          :csh
        when /zsh/
          :zsh
        when /dash/
          :dash
        else
          :unknown
        end
      end

      def setup_autoload
        prelude_path = File.join(__dir__, 'prelude.rb')

        case shell = working_shell_type
        when :bash, :zsh
          puts <<~EOS
          # add the following lines in your ~/.#{shell}_profile

          if test -s #{prelude_path} ; then
            export RUBYOPT='-r #{prelude_path}'
          fi

          # Add `Kernel#bb` method which is alias of `Kernel#debugger`
          # export RUBY_DEBUG_BB=1
          EOS

        when :fish
          puts <<~EOS
          # add the following lines in your ~/.config/fish/config.fish
          set -x RUBYOPT "-r #{__dir__}/prelude" $RUBYOPT
          EOS

        else
          puts "# Sorry that your shell is not supported yet.",
               "# Please use the content in #{prelude_path} as a reference and modify your login script accordingly."
        end
      end

      def cleanup_unix_domain_sockets
        Dir.glob(DEBUGGER__.create_unix_domain_socket_name_prefix + '*') do |file|
          if File.socket?(file) && (/-(\d+)-\d+$/ =~ file || /-(\d+)$/ =~ file)
            begin
              Process.kill(0, $1.to_i)
            rescue Errno::EPERM
            rescue Errno::ESRCH
              File.unlink(file)
            end
          end
        end
      end

      def list_connections
        Dir.glob(DEBUGGER__.create_unix_domain_socket_name_prefix + '*').find_all do |path|
          File.socket?(path)
        end
      end
    end

    def initialize argv
      @multi_process = false
      @pid = nil
      @console = Console.new

      case argv.size
      when 0
        connect_unix
      when 1
        if /\A\d+\z/ =~ (arg = argv.shift.strip)
          connect_tcp nil, arg.to_i
        else
          connect_unix arg
        end
      when 2
        connect_tcp argv[0], argv[1]
      else
        raise CommandLineOptionError
      end

      @width = IO.console_size[1]
      @width = 80 if @width == 0

      send "version: #{VERSION} " +
           "width: #{@width} " +
           "cookie: #{CONFIG[:cookie] || '-'} " +
           "nonstop: #{CONFIG[:nonstop] ? 'true' : 'false'}"
    end

    def deactivate
      @console.deactivate if @console
    end

    def readline
      if @multi_process
        @console.readline "(rdbg:remote\##{@pid}) "
      else
        @console.readline "(rdbg:remote) "
      end
    end

    def connect_unix name = nil
      if name
        if File.exist? name
          @s = Socket.unix(name)
        else
          @s = Socket.unix(File.join(DEBUGGER__.unix_domain_socket_dir, name))
        end
      else
        Client.cleanup_unix_domain_sockets
        files = Client.list_connections

        case files.size
        when 0
          $stderr.puts "No debug session is available."
          exit
        when 1
          @s = Socket.unix(files.first)
        else
          $stderr.puts "Please select a debug session:"
          files.each{|f|
            $stderr.puts "  #{File.basename(f)}"
          }
          exit
        end
      end
    end

    def connect_tcp host, port
      @s = Socket.tcp(host, port)
    end

    def send msg
      p send: msg if $VERBOSE
      @s.puts msg
    end

    def connect
      pre_commands = (CONFIG[:commands] || '').split(';;')

      trap(:SIGINT){
        send "pause"
      }

      begin
        trap(:SIGWINCH){
          @width = IO.console_size[1]
        }
      rescue ArgumentError
        @width = 80
      end

      while line = @s.gets
        p recv: line if $VERBOSE
        case line

        when /^out (.*)/
          puts "#{$1}"

        when /^input (.+)/
          pid = $1
          @multi_process = true if @pid && @pid != pid
          @pid = pid
          prev_trap = trap(:SIGINT, 'DEFAULT')

          begin
            if pre_commands.empty?
              line = readline
            else
              line = pre_commands.shift
              puts "(rdbg:remote:command) #{line}"
            end
          rescue Interrupt
            retry
          ensure
            trap(:SIGINT, prev_trap)
          end

          line = (line || 'quit').strip
          send "command #{pid} #{@width} #{line}"

        when /^ask (\d+) (.*)/
          pid = $1
          print $2
          send "answer #{pid} #{gets || ''}"

        when /^quit/
          raise 'quit'

        else
          puts "(unknown) #{line.inspect}"
        end
      end
    rescue
      STDERR.puts "disconnected (#{$!})"
      exit
    ensure
      deactivate
    end
  end
end

if __FILE__ == $0
  DEBUGGER__::Client.new(argv).connect
end
