# frozen_string_literal: true

require 'socket'
require_relative 'config'
require_relative 'version'

module DEBUGGER__
  class UI_ServerBase < UI_Base
    def initialize
      @sock = @sock_for_fork = nil
      @accept_m = Mutex.new
      @accept_cv = ConditionVariable.new
      @client_addr = nil
      @q_msg = nil
      @q_ans = nil
      @unsent_messages = []
      @width = 80
      @repl = true
      @session = nil
    end

    class Terminate < StandardError; end
    class GreetingError < StandardError; end
    class RetryConnection < StandardError; end

    def deactivate
      @reader_thread.raise Terminate
      @reader_thread.join
    end

    def accept
      if @sock_for_fork
        begin
          yield @sock_for_fork, already_connected: true
        ensure
          @sock_for_fork.close
          @sock_for_fork = nil
        end
      end
    end

    def activate session, on_fork: false
      @session = session
      @reader_thread = Thread.new do
        # An error on this thread should break the system.
        Thread.current.abort_on_exception = true
        Thread.current.name = 'DEBUGGER__::Server::reader'

        accept do |server, already_connected: false|
          DEBUGGER__.warn "Connected."
          greeting_done = false
          @need_pause_at_first = true

          @accept_m.synchronize{
            @sock = server
            greeting
            greeting_done = true

            @accept_cv.signal

            # flush unsent messages
            @unsent_messages.each{|m|
              @sock.puts m
            } if @repl
            @unsent_messages.clear

            @q_msg = Queue.new
            @q_ans = Queue.new
          } unless already_connected

          setup_interrupt do
            pause if !already_connected && @need_pause_at_first
            process
          end

        rescue GreetingError => e
          DEBUGGER__.warn "GreetingError: #{e.message}"
          next
        rescue Terminate
          raise # should catch at outer scope
        rescue RetryConnection
          next
        rescue => e
          DEBUGGER__.warn "ReaderThreadError: #{e}"
          pp e.backtrace
        ensure
          DEBUGGER__.warn "Disconnected."
          cleanup_reader if greeting_done
        end # accept

      rescue Terminate
        # ignore
      end
    end

    def cleanup_reader
      @sock.close if @sock
      @sock = nil
      @q_msg.close
      @q_msg = nil
      @q_ans.close
      @q_ans = nil
    end

    def check_cookie c
      cookie = CONFIG[:cookie]
      if cookie && cookie != c
        raise GreetingError, "Cookie mismatch (#{$2.inspect} was sent)"
      end
    end

    def parse_option params
      case params.strip
      when /width:\s+(\d+)/
        @width = $1.to_i
        parse_option $~.post_match
      when /cookie:\s+(\S+)/
        check_cookie $1 if $1 != '-'
        parse_option $~.post_match
      when /nonstop: (true|false)/
        @need_pause_at_first = false if $1 == 'true'
        parse_option $~.post_match
      when /(.+):(.+)/
        raise GreetingError, "Unkown option: #{params}"
      else
        # OK
      end
    end

    def greeting
      case g = @sock.gets
      when /^info cookie:\s+(.*)$/
        require 'etc'

        check_cookie $1
        @sock.puts "PID: #{Process.pid}, $0: #{$0}, session_name: #{CONFIG[:session_name]}"
        @sock.puts "debug #{VERSION} on #{RUBY_DESCRIPTION}"
        @sock.puts "uname: #{Etc.uname.inspect}"
        @sock.close
        raise GreetingError, "HEAD request"

      when /^version:\s+(\S+)\s+(.+)$/
        v, params = $1, $2

        # TODO: protocol version
        if v != VERSION
          @sock.puts msg = "out DEBUGGER: Incompatible version (server:#{VERSION} and client:#{$1})"
          raise GreetingError, msg
        end
        parse_option(params)

        session_name = CONFIG[:session_name]
        session_name_str = ", session_name:#{session_name}" if session_name
        puts "DEBUGGER (client): Connected. PID:#{Process.pid}, $0:#{$0}#{session_name_str}"
        puts "DEBUGGER (client): Type `Ctrl-C` to enter the debug console." unless @need_pause_at_first
        puts

      when /^Content-Length: (\d+)/
        require_relative 'server_dap'

        raise unless @sock.read(2) == "\r\n"
        self.extend(UI_DAP)
        @repl = false
        @need_pause_at_first = false
        dap_setup @sock.read($1.to_i)

      when /^GET\s\/json\sHTTP\/1.1/, /^GET\s\/json\/version\sHTTP\/1.1/, /^GET\s\/\w{8}-\w{4}-\w{4}-\w{4}-\w{12}\sHTTP\/1.1/
        # The reason for not using @uuid here is @uuid is nil if users run debugger without `--open=chrome`.

        require_relative 'server_cdp'

        self.extend(UI_CDP)
        send_chrome_response g
      else
        raise GreetingError, "Unknown greeting message: #{g}"
      end
    end

    def process
      while true
        DEBUGGER__.debug{ "sleep IO.select" }
        _r = IO.select([@sock])
        DEBUGGER__.debug{ "wakeup IO.select" }

        line = @session.process_group.sync do
          unless IO.select([@sock], nil, nil, 0)
            DEBUGGER__.debug{ "UI_Server can not read" }
            break :can_not_read
          end
          @sock.gets&.chomp.tap{|line|
            DEBUGGER__.debug{ "UI_Server received: #{line}" }
          }
        end

        return unless line
        next if line == :can_not_read

        case line
        when /\Apause/
          pause
        when /\Acommand (\d+) (\d+) ?(.+)/
          raise "not in subsession, but received: #{line.inspect}" unless @session.in_subsession?

          if $1.to_i == Process.pid
            @width = $2.to_i
            @q_msg << $3
          else
            raise "pid:#{Process.pid} but get #{line}"
          end
        when /\Aanswer (\d+) (.*)/
          raise "not in subsession, but received: #{line.inspect}" unless @session.in_subsession?

          if $1.to_i == Process.pid
            @q_ans << $2
          else
            raise "pid:#{Process.pid} but get #{line}"
          end
        else
          STDERR.puts "unsupported: #{line.inspect}"
          exit!
        end
      end
    end

    def remote?
      true
    end

    def width
      @width
    end

    def sigurg_overridden? prev_handler
      case prev_handler
      when "SYSTEM_DEFAULT", "DEFAULT"
        false
      when Proc
        if prev_handler.source_location[0] == __FILE__
          false
        else
          true
        end
      else
        true
      end
    end

    begin
      prev = trap(:SIGURG, nil)
      trap(:SIGURG, prev)
      TRAP_SIGNAL = :SIGURG
    rescue ArgumentError
      # maybe Windows?
      TRAP_SIGNAL = :SIGINT
    end

    def setup_interrupt
      prev_handler = trap(TRAP_SIGNAL) do
        # $stderr.puts "trapped SIGINT"
        ThreadClient.current.on_trap TRAP_SIGNAL

        case prev_handler
        when Proc
          prev_handler.call
        else
          # ignore
        end
      end

      if sigurg_overridden?(prev_handler)
        DEBUGGER__.warn "SIGURG handler is overridden by the debugger."
      end
      yield
    ensure
      trap(TRAP_SIGNAL, prev_handler)
    end

    attr_reader :reader_thread

    class NoRemoteError < Exception; end

    def sock skip: false
      if s = @sock         # already connection
        # ok
      elsif skip == true   # skip process
        no_sock = true
        r = @accept_m.synchronize do
          if @sock
            no_sock = false
          else
            yield nil
          end
        end
        return r if no_sock
      else                 # wait for connection
        until s = @sock
          @accept_m.synchronize{
            unless @sock
              DEBUGGER__.warn "wait for debugger connection..."
              @accept_cv.wait(@accept_m)
            end
          }
        end
      end

      yield s
    rescue Errno::EPIPE
      # ignore
    end

    def ask prompt
      sock do |s|
        s.puts "ask #{Process.pid} #{prompt}"
        @q_ans.pop
      end
    end

    def puts str = nil
      case str
      when Array
        enum = str.each
      when String
        enum = str.each_line
      when nil
        enum = [''].each
      end

      sock skip: true do |s|
        enum.each do |line|
          msg = "out #{line.chomp}"
          if s
            s.puts msg
          else
            @unsent_messages << msg
          end
        end
      end
    end

    def readline prompt
      input = (sock(skip: CONFIG[:skip_bp]) do |s|
        next unless s

        if @repl
          raise "not in subsession, but received: #{line.inspect}" unless @session.in_subsession?
          line = "input #{Process.pid}"
          DEBUGGER__.debug{ "send: #{line}" }
          s.puts line
        end
        sleep 0.01 until @q_msg
        @q_msg.pop.tap{|msg|
          DEBUGGER__.debug{ "readline: #{msg.inspect}" }
        }
      end || 'continue')

      if input.is_a?(String)
        input.strip
      else
        input
      end
    end

    def pause
      # $stderr.puts "DEBUG: pause request"
      Process.kill(TRAP_SIGNAL, Process.pid)
    end

    def quit n, &_b
      # ignore n
      sock do |s|
        s.puts "quit"
      end
    end

    def after_fork_parent
      # do nothing
    end

    def vscode_setup debug_port
      require_relative 'server_dap'
      UI_DAP.setup debug_port
    end
  end

  class UI_TcpServer < UI_ServerBase
    def initialize host: nil, port: nil
      @local_addr = nil
      @host = host || CONFIG[:host]
      @port_save_file = nil
      @port = begin
        port_str = (port && port.to_s) || CONFIG[:port] || raise("Specify listening port by RUBY_DEBUG_PORT environment variable.")
        case port_str
        when /\A\d+\z/
          port_str.to_i
        when /\A(\d+):(.+)\z/
          @port_save_file = $2
          $1.to_i
        else
          raise "Specify digits for port number"
        end
      end
      @uuid = nil # for CDP

      super()
    end

    def chrome_setup
      require_relative 'server_cdp'

      @uuid = SecureRandom.uuid
      @chrome_pid = UI_CDP.setup_chrome(@local_addr.inspect_sockaddr, @uuid)
      DEBUGGER__.warn <<~EOS
        With Chrome browser, type the following URL in the address-bar:

           devtools://devtools/bundled/inspector.html?v8only=true&panel=sources&noJavaScriptCompletion=true&ws=#{@local_addr.inspect_sockaddr}/#{@uuid}

        EOS
    end

    def accept
      retry_cnt = 0
      super # for fork

      begin
        Socket.tcp_server_sockets @host, @port do |socks|
          @local_addr = socks.first.local_address # Change this part if `socks` are multiple.
          rdbg = File.expand_path('../../exe/rdbg', __dir__)
          DEBUGGER__.warn "Debugger can attach via TCP/IP (#{@local_addr.inspect_sockaddr})"

          if @port_save_file
            File.write(@port_save_file, "#{socks[0].local_address.ip_port.to_s}\n")
            DEBUGGER__.warn "Port is saved into #{@port_save_file}"
          end

          DEBUGGER__.info <<~EOS
          With rdbg, use the following command line:
          #
          #   #{rdbg} --attach #{@local_addr.ip_address} #{@local_addr.ip_port}
          #
          EOS

          case CONFIG[:open]
          when 'chrome'
            chrome_setup
          when 'vscode'
            vscode_setup @local_addr.inspect_sockaddr
          end

          Socket.accept_loop(socks) do |sock, client|
            @client_addr = client
            yield @sock_for_fork = sock
          end
        end
      rescue Errno::EADDRINUSE
        if retry_cnt < 10
          retry_cnt += 1
          sleep 0.1
          retry
        else
          raise
        end
      rescue Terminate
        # OK
      rescue => e
        $stderr.puts e.inspect, e.message
        pp e.backtrace
        exit
      end
    ensure
      @sock_for_fork = nil

      if @port_save_file && File.exist?(@port_save_file)
        File.unlink(@port_save_file)
      end
    end
  end

  class UI_UnixDomainServer < UI_ServerBase
    def initialize sock_dir: nil, sock_path: nil
      @sock_path = sock_path
      @sock_dir = sock_dir || DEBUGGER__.unix_domain_socket_dir
      @sock_for_fork = nil

      super()
    end

    def accept
      super # for fork

      case
      when @sock_path
      when sp = CONFIG[:sock_path]
        @sock_path = sp
      else
        @sock_path = DEBUGGER__.create_unix_domain_socket_name(@sock_dir)
      end

      ::DEBUGGER__.warn "Debugger can attach via UNIX domain socket (#{@sock_path})"
      vscode_setup @sock_path if CONFIG[:open] == 'vscode'

      begin
        Socket.unix_server_loop @sock_path do |sock, client|
          @sock_for_fork = sock
          @client_addr = client

          yield sock
        ensure
          sock.close
          @sock_for_fork = nil
        end
      rescue Errno::ECONNREFUSED => _e
        ::DEBUGGER__.warn "#{_e.message} (socket path: #{@sock_path})"

        if @sock_path.start_with? Config.unix_domain_socket_tmpdir
          # try on homedir
          @sock_path = Config.create_unix_domain_socket_name(unix_domain_socket_homedir)
          ::DEBUGGER__.warn "retry with #{@sock_path}"
          retry
        else
          raise
        end
      end
    end
  end
end
