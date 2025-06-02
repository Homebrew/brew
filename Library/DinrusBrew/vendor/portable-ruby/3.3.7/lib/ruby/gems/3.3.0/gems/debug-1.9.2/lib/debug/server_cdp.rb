# frozen_string_literal: true

require 'json'
require 'digest/sha1'
require 'securerandom'
require 'stringio'
require 'open3'
require 'tmpdir'
require 'tempfile'
require 'timeout'

module DEBUGGER__
  module UI_CDP
    SHOW_PROTOCOL = ENV['RUBY_DEBUG_CDP_SHOW_PROTOCOL'] == '1'

    class UnsupportedError < StandardError; end
    class NotFoundChromeEndpointError < StandardError; end

    class << self
      def setup_chrome addr, uuid
        return if CONFIG[:chrome_path] == ''

        port, path, pid = run_new_chrome
        begin
          s = Socket.tcp '127.0.0.1', port
        rescue Errno::ECONNREFUSED, Errno::EADDRNOTAVAIL
          return
        end

        ws_client = WebSocketClient.new(s)
        ws_client.handshake port, path
        ws_client.send id: 1, method: 'Target.getTargets'

        loop do
          res = ws_client.extract_data
          case res['id']
          when 1
            target_info = res.dig('result', 'targetInfos')
            page = target_info.find{|t| t['type'] == 'page'}
            ws_client.send id: 2, method: 'Target.attachToTarget',
                          params: {
                            targetId: page['targetId'],
                            flatten: true
                          }
          when 2
            s_id = res.dig('result', 'sessionId')
            # TODO: change id
            ws_client.send sessionId: s_id, id: 100, method: 'Network.enable'
            ws_client.send sessionId: s_id, id: 3,
                          method: 'Page.enable'
          when 3
            s_id = res['sessionId']
            ws_client.send sessionId: s_id, id: 4,
                          method: 'Page.getFrameTree'
          when 4
            s_id = res['sessionId']
            f_id = res.dig('result', 'frameTree', 'frame', 'id')
            ws_client.send sessionId: s_id, id: 5,
                          method: 'Page.navigate',
                          params: {
                            url: "devtools://devtools/bundled/inspector.html?v8only=true&panel=sources&noJavaScriptCompletion=true&ws=#{addr}/#{uuid}",
                            frameId: f_id
                          }
          when 101
            break
          else
            if res['method'] == 'Network.webSocketWillSendHandshakeRequest'
              s_id = res['sessionId']
              # Display the console by entering ESC key
              ws_client.send sessionId: s_id, id: 101,  # TODO: change id
                            method:"Input.dispatchKeyEvent",
                            params: {
                              type:"keyDown",
                              windowsVirtualKeyCode:27 # ESC key
                            }
            end
          end
        end
        pid
      rescue Errno::ENOENT, UnsupportedError, NotFoundChromeEndpointError
        nil
      end

      TIMEOUT_SEC = 5

      def run_new_chrome
        path = CONFIG[:chrome_path]

        data = nil
        port = nil
        wait_thr = nil

        # The process to check OS is based on `selenium` project.
        case RbConfig::CONFIG['host_os']
        when /mswin|msys|mingw|cygwin|emc/
          if path.nil?
            candidates = ['C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe', 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe']
            path = get_chrome_path candidates
          end
          # The path is based on https://github.com/sindresorhus/open/blob/v8.4.0/index.js#L128.
          stdin, stdout, stderr, wait_thr = *Open3.popen3("#{ENV['SystemRoot']}\\System32\\WindowsPowerShell\\v1.0\\powershell")
          tf = Tempfile.create(['debug-', '.txt'])

          stdin.puts("Start-process '#{path}' -Argumentlist '--remote-debugging-port=0', '--no-first-run', '--no-default-browser-check', '--user-data-dir=C:\\temp' -Wait -RedirectStandardError #{tf.path}")
          stdin.close
          stdout.close
          stderr.close
          port, path = get_devtools_endpoint(tf.path)

          at_exit{
            DEBUGGER__.skip_all

            stdin, stdout, stderr, wait_thr = *Open3.popen3("#{ENV['SystemRoot']}\\System32\\WindowsPowerShell\\v1.0\\powershell")
            stdin.puts("Stop-process -Name chrome")
            stdin.close
            stdout.close
            stderr.close
            tf.close
            begin
              File.unlink(tf)
            rescue Errno::EACCES
            end
          }
        when /darwin|mac os/
          path = path || '/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome'
          dir = Dir.mktmpdir
          # The command line flags are based on: https://developer.mozilla.org/en-US/docs/Tools/Remote_Debugging/Chrome_Desktop#connecting.
          stdin, stdout, stderr, wait_thr = *Open3.popen3("#{path} --remote-debugging-port=0 --no-first-run --no-default-browser-check --user-data-dir=#{dir}")
          stdin.close
          stdout.close
          data = stderr.readpartial 4096
          stderr.close
          if data.match(/DevTools listening on ws:\/\/127.0.0.1:(\d+)(.*)/)
            port = $1
            path = $2
          end

          at_exit{
            DEBUGGER__.skip_all
            FileUtils.rm_rf dir
          }
        when /linux/
          path = path || 'google-chrome'
          dir = Dir.mktmpdir
          # The command line flags are based on: https://developer.mozilla.org/en-US/docs/Tools/Remote_Debugging/Chrome_Desktop#connecting.
          stdin, stdout, stderr, wait_thr = *Open3.popen3("#{path} --remote-debugging-port=0 --no-first-run --no-default-browser-check --user-data-dir=#{dir}")
          stdin.close
          stdout.close
          data = ''
          begin
            Timeout.timeout(TIMEOUT_SEC) do
              until data.match?(/DevTools listening on ws:\/\/127.0.0.1:\d+.*/)
                data = stderr.readpartial 4096
              end
            end
          rescue Exception
            raise NotFoundChromeEndpointError
          end
          stderr.close
          if data.match(/DevTools listening on ws:\/\/127.0.0.1:(\d+)(.*)/)
            port = $1
            path = $2
          end

          at_exit{
            DEBUGGER__.skip_all
            FileUtils.rm_rf dir
          }
        else
          raise UnsupportedError
        end

        [port, path, wait_thr.pid]
      end

      def get_chrome_path candidates
        candidates.each{|c|
          if File.exist? c
            return c
          end
        }
        raise UnsupportedError
      end

      ITERATIONS = 50

      def get_devtools_endpoint tf
        i = 1
        while i < ITERATIONS
          i += 1
          if File.exist?(tf) && data = File.read(tf)
            if data.match(/DevTools listening on ws:\/\/127.0.0.1:(\d+)(.*)/)
              port = $1
              path = $2
              return [port, path]
            end
          end
          sleep 0.1
        end
        raise NotFoundChromeEndpointError
      end
    end

    def send_chrome_response req
      @repl = false
      case req
      when /^GET\s\/json\/version\sHTTP\/1.1/
        body = {
          Browser: "ruby/v#{RUBY_VERSION}",
          'Protocol-Version': "1.1"
        }
        send_http_res body
        raise UI_ServerBase::RetryConnection

      when /^GET\s\/json\sHTTP\/1.1/
        @uuid = @uuid || SecureRandom.uuid
        addr = @local_addr.inspect_sockaddr
        body = [{
          description: "ruby instance",
          devtoolsFrontendUrl: "devtools://devtools/bundled/inspector.html?experiments=true&v8only=true&ws=#{addr}/#{@uuid}",
          id: @uuid,
          title: $0,
          type: "node",
          url: "file://#{File.absolute_path($0)}",
          webSocketDebuggerUrl: "ws://#{addr}/#{@uuid}"
        }]
        send_http_res body
        raise UI_ServerBase::RetryConnection

      when /^GET\s\/(\w{8}-\w{4}-\w{4}-\w{4}-\w{12})\sHTTP\/1.1/
        raise 'Incorrect uuid' unless $1 == @uuid

        @need_pause_at_first = false
        CONFIG.set_config no_color: true

        @ws_server = WebSocketServer.new(@sock)
        @ws_server.handshake
      end
    end

    def send_http_res body
      json = JSON.generate body
      header = "HTTP/1.0 200 OK\r\nContent-Type: application/json; charset=UTF-8\r\nCache-Control: no-cache\r\nContent-Length: #{json.bytesize}\r\n\r\n"
      @sock.puts "#{header}#{json}"
    end

    module WebSocketUtils
      class Frame
        attr_reader :b

        def initialize
          @b = ''.b
        end

        def << obj
          case obj
          when String
            @b << obj.b
          when Enumerable
            obj.each{|e| self << e}
          end
        end

        def char bytes
          @b << bytes
        end

        def ulonglong bytes
          @b << [bytes].pack('Q>')
        end

        def uint16 bytes
          @b << [bytes].pack('n*')
        end
      end

      def show_protocol dir, msg
        if DEBUGGER__::UI_CDP::SHOW_PROTOCOL
          $stderr.puts "\#[#{dir}] #{msg}"
        end
      end
    end

    class WebSocketClient
      include WebSocketUtils

      def initialize s
        @sock = s
      end

      def handshake port, path
        key = SecureRandom.hex(11)
        req = "GET #{path} HTTP/1.1\r\nHost: 127.0.0.1:#{port}\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: #{key}==\r\n\r\n"
        show_protocol :>, req
        @sock.print req
        res = @sock.readpartial 4092
        show_protocol :<, res

        if res.match(/^Sec-WebSocket-Accept: (.*)\r\n/)
          correct_key = Digest::SHA1.base64digest "#{key}==258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
          raise "The Sec-WebSocket-Accept value: #{$1} is not valid" unless $1 == correct_key
        else
          raise "Unknown response: #{res}"
        end
      end

      def send **msg
        msg = JSON.generate(msg)
        show_protocol :>, msg
        frame = Frame.new
        fin = 0b10000000
        opcode = 0b00000001
        frame.char fin + opcode

        mask = 0b10000000 # A client must mask all frames in a WebSocket Protocol.
        bytesize = msg.bytesize
        if bytesize < 126
          payload_len = bytesize
          frame.char mask + payload_len
        elsif bytesize < 2 ** 16
          payload_len = 0b01111110
          frame.char mask + payload_len
          frame.uint16 bytesize
        elsif bytesize < 2 ** 64
          payload_len = 0b01111111
          frame.char mask + payload_len
          frame.ulonglong bytesize
        else
          raise 'Bytesize is too big.'
        end

        masking_key = 4.times.map{
          key = rand(1..255)
          frame.char key
          key
        }
        msg.bytes.each_with_index do |b, i|
          frame.char(b ^ masking_key[i % 4])
        end

        @sock.print frame.b
      end

      def extract_data
        first_group = @sock.getbyte
        fin = first_group & 0b10000000 != 128
        raise 'Unsupported' if fin
        opcode = first_group & 0b00001111
        raise "Unsupported: #{opcode}" unless opcode == 1

        second_group = @sock.getbyte
        mask = second_group & 0b10000000 == 128
        raise 'The server must not mask any frames' if mask
        payload_len = second_group & 0b01111111
        # TODO: Support other payload_lengths
        if payload_len == 126
          payload_len = @sock.read(2).unpack('n*')[0]
        end

        msg = @sock.read payload_len
        show_protocol :<, msg
        JSON.parse msg
      end
    end

    class Detach < StandardError
    end

    class WebSocketServer
      include WebSocketUtils

      def initialize s
        @sock = s
      end

      def handshake
        req = @sock.readpartial 4096
        show_protocol '>', req

        if req.match(/^Sec-WebSocket-Key: (.*)\r\n/)
          accept = Digest::SHA1.base64digest "#{$1}258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
          res = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: #{accept}\r\n\r\n"
          @sock.print res
          show_protocol :<, res
        else
          "Unknown request: #{req}"
        end
      end

      def send **msg
        msg = JSON.generate(msg)
        show_protocol :<, msg
        frame = Frame.new
        fin = 0b10000000
        opcode = 0b00000001
        frame.char fin + opcode

        mask = 0b00000000 # A server must not mask any frames in a WebSocket Protocol.
        bytesize = msg.bytesize
        if bytesize < 126
          payload_len = bytesize
          frame.char mask + payload_len
        elsif bytesize < 2 ** 16
          payload_len = 0b01111110
          frame.char mask + payload_len
          frame.uint16 bytesize
        elsif bytesize < 2 ** 64
          payload_len = 0b01111111
          frame.char mask + payload_len
          frame.ulonglong bytesize
        else
          raise 'Bytesize is too big.'
        end

        frame << msg
        @sock.print frame.b
      end

      def extract_data
        first_group = @sock.getbyte
        fin = first_group & 0b10000000 != 128
        raise 'Unsupported' if fin

        opcode = first_group & 0b00001111
        raise Detach if opcode == 8
        raise "Unsupported: #{opcode}" unless opcode == 1

        second_group = @sock.getbyte
        mask = second_group & 0b10000000 == 128
        raise 'The client must mask all frames' unless mask
        payload_len = second_group & 0b01111111
        # TODO: Support other payload_lengths
        if payload_len == 126
          payload_len = @sock.gets(2).unpack('n*')[0]
        end

        masking_key = []
        4.times { masking_key << @sock.getbyte }
        unmasked = []
        payload_len.times do |n|
          masked = @sock.getbyte
          unmasked << (masked ^ masking_key[n % 4])
        end
        msg = unmasked.pack 'c*'
        show_protocol :>, msg
        JSON.parse msg
      end
    end

    def send_response req, **res
      @ws_server.send id: req['id'], result: res
    end

    def send_fail_response req, **res
      @ws_server.send id: req['id'], error: res
    end

    def send_event method, **params
      @ws_server.send method: method, params: params
    end

    INVALID_REQUEST = -32600

    def process
      bps = {}
      @src_map = {}
      loop do
        req = @ws_server.extract_data

        case req['method']

        ## boot/configuration
        when 'Debugger.getScriptSource'
          @q_msg << req
        when 'Debugger.enable'
          send_response req, debuggerId: rand.to_s
          @q_msg << req
        when 'Runtime.enable'
          send_response req
          send_event 'Runtime.executionContextCreated',
                      context: {
                        id: SecureRandom.hex(16),
                        origin: "http://#{@local_addr.inspect_sockaddr}",
                        name: ''
                      }
        when 'Runtime.getIsolateId'
          send_response req,
                        id: SecureRandom.hex
        when 'Runtime.terminateExecution'
          send_response req
          exit
        when 'Page.startScreencast', 'Emulation.setTouchEmulationEnabled', 'Emulation.setEmitTouchEventsForMouse',
          'Runtime.compileScript', 'Page.getResourceContent', 'Overlay.setPausedInDebuggerMessage',
          'Runtime.releaseObjectGroup', 'Runtime.discardConsoleEntries', 'Log.clear', 'Runtime.runIfWaitingForDebugger'
          send_response req

        ## control
        when 'Debugger.resume'
          send_response req
          send_event 'Debugger.resumed'
          @q_msg << 'c'
          @q_msg << req
        when 'Debugger.stepOver'
          begin
            @session.check_postmortem
            send_response req
            send_event 'Debugger.resumed'
            @q_msg << 'n'
          rescue PostmortemError
            send_fail_response req,
                              code: INVALID_REQUEST,
                              message: "'stepOver' is not supported while postmortem mode"
          ensure
            @q_msg << req
          end
        when 'Debugger.stepInto'
          begin
            @session.check_postmortem
            send_response req
            send_event 'Debugger.resumed'
            @q_msg << 's'
          rescue PostmortemError
            send_fail_response req,
                              code: INVALID_REQUEST,
                              message: "'stepInto' is not supported while postmortem mode"
          ensure
            @q_msg << req
          end
        when 'Debugger.stepOut'
          begin
            @session.check_postmortem
            send_response req
            send_event 'Debugger.resumed'
            @q_msg << 'fin'
          rescue PostmortemError
            send_fail_response req,
                              code: INVALID_REQUEST,
                              message: "'stepOut' is not supported while postmortem mode"
          ensure
            @q_msg << req
          end
        when 'Debugger.setSkipAllPauses'
          skip = req.dig('params', 'skip')
          if skip
            deactivate_bp
          else
            activate_bp bps
          end
          send_response req
        when 'Debugger.pause'
          send_response req
          Process.kill(UI_ServerBase::TRAP_SIGNAL, Process.pid)

        # breakpoint
        when 'Debugger.getPossibleBreakpoints'
          @q_msg << req
        when 'Debugger.setBreakpointByUrl'
          line = req.dig('params', 'lineNumber')
          if regexp = req.dig('params', 'urlRegex')
            b_id = "1:#{line}:#{regexp}"
            bps[b_id] = bps.size
            path = regexp.match(/(.*)\|/)[1].gsub("\\", "")
            add_line_breakpoint(req, b_id, path)
          elsif url = req.dig('params', 'url')
            b_id = "#{line}:#{url}"
            # When breakpoints are set in Script snippet, non-existent path such as "snippet:///Script%20snippet%20%231" sent.
            # That's why we need to check it here.
            if File.exist? url
              bps[b_id] = bps.size
              add_line_breakpoint(req, b_id, url)
            else
              send_response req,
                            breakpointId: b_id,
                            locations: []
            end            
          else
            if hash = req.dig('params', 'scriptHash')
              b_id = "#{line}:#{hash}"
              send_response req,
                            breakpointId: b_id,
                            locations: []
            else
              raise 'Unsupported'
            end
          end
        when 'Debugger.removeBreakpoint'
          b_id = req.dig('params', 'breakpointId')
          bps = del_bp bps, b_id
          send_response req
        when 'Debugger.setBreakpointsActive'
          active = req.dig('params', 'active')
          if active
            activate_bp bps
          else
            deactivate_bp # TODO: Change this part because catch breakpoints should not be deactivated.
          end
          send_response req
        when 'Debugger.setPauseOnExceptions'
          state = req.dig('params', 'state')
          ex = 'Exception'
          case state
          when 'none'
            @q_msg << 'config postmortem = false'
            bps = del_bp bps, ex
          when 'uncaught'
            @q_msg << 'config postmortem = true'
            bps = del_bp bps, ex
          when 'all'
            @q_msg << 'config postmortem = false'
            SESSION.add_catch_breakpoint ex
            bps[ex] = bps.size
          end
          send_response req

        when 'Debugger.evaluateOnCallFrame', 'Runtime.getProperties'
          @q_msg << req
        end
      end
    rescue Detach
      @q_msg << 'continue'
    end

    def add_line_breakpoint req, b_id, path
      cond = req.dig('params', 'condition')
      line = req.dig('params', 'lineNumber')
      src = get_source_code path
      end_line = src.lines.count
      line = end_line  if line > end_line
      if cond != ''
        SESSION.add_line_breakpoint(path, line + 1, cond: cond)
      else
        SESSION.add_line_breakpoint(path, line + 1)
      end
      # Because we need to return scriptId, responses are returned in SESSION thread.
      req['params']['scriptId'] = path
      req['params']['lineNumber'] = line
      req['params']['breakpointId'] = b_id
      @q_msg << req
    end

    def del_bp bps, k
      return bps unless idx = bps[k]

      bps.delete k
      bps.each_key{|i| bps[i] -= 1 if bps[i] > idx}
      @q_msg << "del #{idx}"
      bps
    end

    def get_source_code path
      return @src_map[path] if @src_map[path]

      src = File.read(path)
      @src_map[path] = src
      src
    end

    def activate_bp bps
      bps.each_key{|k|
        if k.match(/^\d+:(\d+):(.*)/)
          line = $1
          path = $2
          SESSION.add_line_breakpoint(path, line.to_i + 1)
        else
          SESSION.add_catch_breakpoint 'Exception'
        end
      }
    end

    def deactivate_bp
      @q_msg << 'del'
      @q_ans << 'y'
    end

    def cleanup_reader
      super
      Process.kill :KILL, @chrome_pid if @chrome_pid
    rescue Errno::ESRCH # continue if @chrome_pid process is not found
    end

    ## Called by the SESSION thread

    alias respond send_response
    alias respond_fail send_fail_response
    alias fire_event send_event

    def sock skip: false
      yield $stderr
    end

    def puts result=''
      # STDERR.puts "puts: #{result}"
      # send_event 'output', category: 'stderr', output: "PUTS!!: " + result.to_s
    end
  end

  class Session
    include GlobalVariablesHelper

    # FIXME: unify this method with ThreadClient#propertyDescriptor.
    def get_type obj
      case obj
      when Array
        ['object', 'array']
      when Hash
        ['object', 'map']
      when String
        ['string']
      when TrueClass, FalseClass
        ['boolean']
      when Symbol
        ['symbol']
      when Integer, Float
        ['number']
      when Exception
        ['object', 'error']
      else
        ['object']
      end
    end

    def fail_response req, **result
      @ui.respond_fail req, **result
      return :retry
    end

    INVALID_PARAMS = -32602
    INTERNAL_ERROR = -32603

    def process_protocol_request req
      case req['method']
      when 'Debugger.stepOver', 'Debugger.stepInto', 'Debugger.stepOut', 'Debugger.resume', 'Debugger.enable'
        request_tc [:cdp, :backtrace, req]
      when 'Debugger.evaluateOnCallFrame'
        frame_id = req.dig('params', 'callFrameId')
        group = req.dig('params', 'objectGroup')
        if fid = @frame_map[frame_id]
          expr = req.dig('params', 'expression')
          request_tc [:cdp, :evaluate, req, fid, expr, group]
        else
          fail_response req,
                        code: INVALID_PARAMS,
                        message: "'callFrameId' is an invalid"
        end
      when 'Runtime.getProperties', 'Runtime.getExceptionDetails'
        oid = req.dig('params', 'objectId') || req.dig('params', 'errorObjectId')
        if ref = @obj_map[oid]
          case ref[0]
          when 'local'
            frame_id = ref[1]
            fid = @frame_map[frame_id]
            request_tc [:cdp, :scope, req, fid]
          when 'global'
            vars = safe_global_variables.sort.map do |name|
              begin
                gv = eval(name.to_s)
              rescue Errno::ENOENT
                gv = nil
              end
              prop = {
                name: name,
                value: {
                  description: gv.inspect
                },
                configurable: true,
                enumerable: true
              }
              type, subtype = get_type(gv)
              prop[:value][:type] = type
              prop[:value][:subtype] = subtype if subtype
              prop
            end

            @ui.respond req, result: vars
            return :retry
          when 'properties'
            request_tc [:cdp, :properties, req, oid]
          when 'exception'
            request_tc [:cdp, :exception, req, oid]
          when 'script'
            # TODO: Support script and global types
            @ui.respond req, result: []
            return :retry
          else
            raise "Unknown type: #{ref.inspect}"
          end
        else
          fail_response req,
                        code: INVALID_PARAMS,
                        message: "'objectId' is an invalid"
        end
      when 'Debugger.getScriptSource'
        s_id = req.dig('params', 'scriptId')
        if src = @src_map[s_id]
          @ui.respond req, scriptSource: src
        else
          fail_response req,
                        code: INVALID_PARAMS,
                        message: "'scriptId' is an invalid"
        end
        return :retry
      when 'Debugger.getPossibleBreakpoints'
        s_id = req.dig('params', 'start', 'scriptId')
        if src = @src_map[s_id]
          lineno = req.dig('params', 'start', 'lineNumber')
          end_line = src.lines.count
          lineno = end_line  if lineno > end_line
          @ui.respond req,
                      locations: [{
                        scriptId: s_id,
                        lineNumber: lineno
                      }]
        else
          fail_response req,
                        code: INVALID_PARAMS,
                        message: "'scriptId' is an invalid"
        end
        return :retry
      when 'Debugger.setBreakpointByUrl'
        path = req.dig('params', 'scriptId')
        if s_id = @scr_id_map[path]
          lineno = req.dig('params', 'lineNumber')
          b_id = req.dig('params', 'breakpointId')
          @ui.respond req,
                      breakpointId: b_id,
                      locations: [{
                          scriptId: s_id,
                          lineNumber: lineno
                      }]
        else
          fail_response req,
                        code: INTERNAL_ERROR,
                        message: 'The target script is not found...'
        end
        return :retry
      end
    end

    def process_protocol_result args
      type, req, result = args

      case type
      when :backtrace
        result[:callFrames].each.with_index do |frame, i|
          frame_id = frame[:callFrameId]
          @frame_map[frame_id] = i
          path = frame[:url]
          unless s_id = @scr_id_map[path]
            s_id = (@scr_id_map.size + 1).to_s
            @scr_id_map[path] = s_id
            lineno = 0
            src = ''
            if path && File.exist?(path)
              src = File.read(path)
              @src_map[s_id] = src
              lineno = src.lines.count
            end
            @ui.fire_event 'Debugger.scriptParsed',
                          scriptId: s_id,
                          url: path,
                          startLine: 0,
                          startColumn: 0,
                          endLine: lineno,
                          endColumn: 0,
                          executionContextId: 1,
                          hash: src.hash.inspect
          end
          frame[:location][:scriptId] = s_id
          frame[:functionLocation][:scriptId] = s_id

          frame[:scopeChain].each {|s|
            oid = s.dig(:object, :objectId)
            @obj_map[oid] = [s[:type], frame_id]
          }
        end

        if oid = result.dig(:data, :objectId)
          @obj_map[oid] = ['properties']
        end
        @ui.fire_event 'Debugger.paused', **result
      when :evaluate
        message = result.delete :message
        if message
          fail_response req,
                        code: INVALID_PARAMS,
                        message: message
        else
          src = req.dig('params', 'expression')
          s_id = (@src_map.size + 1).to_s
          @src_map[s_id] = src
          lineno = src.lines.count
          @ui.fire_event 'Debugger.scriptParsed',
                            scriptId: s_id,
                            url: '',
                            startLine: 0,
                            startColumn: 0,
                            endLine: lineno,
                            endColumn: 0,
                            executionContextId: 1,
                            hash: src.hash.inspect
          if exc = result.dig(:response, :exceptionDetails)
            exc[:stackTrace][:callFrames].each{|frame|
              if frame[:url].empty?
                frame[:scriptId] = s_id
              else
                path = frame[:url]
                unless s_id = @scr_id_map[path]
                  s_id = (@scr_id_map.size + 1).to_s
                  @scr_id_map[path] = s_id
                end
                frame[:scriptId] = s_id
              end
            }
            if oid = exc[:exception][:objectId]
              @obj_map[oid] = ['exception']
            end
          end
          rs = result.dig(:response, :result)
          [rs].each{|obj|
            if oid = obj[:objectId]
              @obj_map[oid] = ['properties']
            end
          }
          @ui.respond req, **result[:response]

          out = result[:output]
          if out && !out.empty?
            @ui.fire_event 'Runtime.consoleAPICalled',
                            type: 'log',
                            args: [
                              type: out.class,
                              value: out
                            ],
                            executionContextId: 1, # Change this number if something goes wrong.
                            timestamp: Time.now.to_f
          end
        end
      when :scope
        result.each{|obj|
          if oid = obj.dig(:value, :objectId)
            @obj_map[oid] = ['properties']
          end
        }
        @ui.respond req, result: result
      when :properties
        result.each_value{|v|
          v.each{|obj|
            if oid = obj.dig(:value, :objectId)
              @obj_map[oid] = ['properties']
            end
          }
        }
        @ui.respond req, **result
      when :exception
        @ui.respond req, **result
      end
    end
  end

  class ThreadClient
    def process_cdp args
      type = args.shift
      req = args.shift

      case type
      when :backtrace
        exception = nil
        result = {
          reason: 'other',
          callFrames: @target_frames.map.with_index{|frame, i|
            exception = frame.raised_exception if frame == current_frame && frame.has_raised_exception

            path = frame.realpath || frame.path

            if frame.iseq.nil?
              lineno = 0
            else
              lineno = frame.iseq.first_line - 1
            end

            {
              callFrameId: SecureRandom.hex(16),
              functionName: frame.name,
              functionLocation: {
                # scriptId: N, # filled by SESSION
                lineNumber: lineno
              },
              location: {
                # scriptId: N, # filled by SESSION
                lineNumber: frame.location.lineno - 1 # The line number is 0-based.
              },
              url: path,
              scopeChain: [
                {
                  type: 'local',
                  object: {
                    type: 'object',
                    objectId: rand.to_s
                  }
                },
                {
                  type: 'script',
                  object: {
                    type: 'object',
                    objectId: rand.to_s
                  }
                },
                {
                  type: 'global',
                  object: {
                    type: 'object',
                    objectId: rand.to_s
                  }
                }
              ],
              this: {
                type: 'object'
              }
            }
          }
        }

        if exception
          result[:data] = evaluate_result exception
          result[:reason] = 'exception'
        end
        event! :protocol_result, :backtrace, req, result
      when :evaluate
        res = {}
        fid, expr, group = args
        frame = @target_frames[fid]
        message = nil

        if frame && (b = frame.eval_binding)
          special_local_variables frame do |name, var|
            b.local_variable_set(name, var) if /\%/ !~name
          end

          result = nil

          case group
          when 'popover'
            case expr
            # Chrome doesn't read instance variables
            when /\A\$\S/
              safe_global_variables.each{|gvar|
                if gvar.to_s == expr
                  result = eval(gvar.to_s)
                  break false
                end
              } and (message = "Error: Not defined global variable: #{expr.inspect}")
            when /(\A((::[A-Z]|[A-Z])\w*)+)/
              unless result = search_const(b, $1)
                message = "Error: Not defined constant: #{expr.inspect}"
              end
            else
              begin
                result = b.local_variable_get(expr)
              rescue NameError
                # try to check method
                if M_RESPOND_TO_P.bind_call(b.receiver, expr, include_all: true)
                  result = M_METHOD.bind_call(b.receiver, expr)
                else
                  message = "Error: Can not evaluate: #{expr.inspect}"
                end
              end
            end
          when 'console', 'watch-group'
            begin
              orig_stdout = $stdout
              $stdout = StringIO.new
              result = b.eval(expr.to_s, '(DEBUG CONSOLE)')
            rescue Exception => e
              result = e
              res[:exceptionDetails] = exceptionDetails(e, 'Uncaught')
            ensure
              output = $stdout.string
              $stdout = orig_stdout
            end
          else
            message = "Error: unknown objectGroup: #{group}"
          end
        else
          result = Exception.new("Error: Can not evaluate on this frame")
        end

        res[:result] = evaluate_result(result)
        event! :protocol_result, :evaluate, req, message: message, response: res, output: output
      when :scope
        fid = args.shift
        frame = @target_frames[fid]
        if b = frame.binding
          vars = b.local_variables.map{|name|
            v = b.local_variable_get(name)
            variable(name, v)
          }
          special_local_variables frame do |name, val|
            vars.unshift variable(name, val)
          end
          vars.unshift variable('%self', b.receiver)
        elsif lvars = frame.local_variables
          vars = lvars.map{|var, val|
            variable(var, val)
          }
        else
          vars = [variable('%self', frame.self)]
          special_local_variables frame do |name, val|
            vars.unshift variable(name, val)
          end
        end
        event! :protocol_result, :scope, req, vars
      when :properties
        oid = args.shift
        result = []
        prop = []

        if obj = @obj_map[oid]
          case obj
          when Array
            result = obj.map.with_index{|o, i|
              variable i.to_s, o
            }
          when Hash
            result = obj.map{|k, v|
              variable(k, v)
            }
          when Struct
            result = obj.members.map{|m|
              variable(m, obj[m])
            }
          when String
            prop = [
              internalProperty('#length', obj.length),
              internalProperty('#encoding', obj.encoding)
            ]
          when Class, Module
            result = obj.instance_variables.map{|iv|
              variable(iv, obj.instance_variable_get(iv))
            }
            prop = [internalProperty('%ancestors', obj.ancestors[1..])]
          when Range
            prop = [
              internalProperty('#begin', obj.begin),
              internalProperty('#end', obj.end),
            ]
          end

          result += M_INSTANCE_VARIABLES.bind_call(obj).map{|iv|
            variable(iv, M_INSTANCE_VARIABLE_GET.bind_call(obj, iv))
          }
          prop += [internalProperty('#class', M_CLASS.bind_call(obj))]
        end
        event! :protocol_result, :properties, req, result: result, internalProperties: prop
      when :exception
        oid = args.shift
        exc = nil
        if obj = @obj_map[oid]
          exc = exceptionDetails obj, obj.to_s
        end
        event! :protocol_result, :exception, req, exceptionDetails: exc
      end
    end

    def exceptionDetails exc, text
      frames = [
        {
          columnNumber: 0,
          functionName: 'eval',
          lineNumber: 0,
          url: ''
        }
      ]
      exc.backtrace_locations&.each do |loc|
        break if loc.path == __FILE__
        path = loc.absolute_path || loc.path
        frames << {
          columnNumber: 0,
          functionName: loc.base_label,
          lineNumber: loc.lineno - 1,
          url: path
        }
      end
      {
        exceptionId: 1,
        text: text,
        lineNumber: 0,
        columnNumber: 0,
        exception: evaluate_result(exc),
        stackTrace: {
          callFrames: frames
        }
      }
    end

    def search_const b, expr
      cs = expr.delete_prefix('::').split('::')
      [Object, *b.eval('::Module.nesting')].reverse_each{|mod|
        if cs.all?{|c|
             if mod.const_defined?(c)
               begin
                 mod = mod.const_get(c)
               rescue Exception
                 false
               end
             else
               false
             end
           }
          # if-body
          return mod
        end
      }
      false
    end

    def evaluate_result r
      v = variable nil, r
      v[:value]
    end

    def internalProperty name, obj
      v = variable name, obj
      v.delete :configurable
      v.delete :enumerable
      v
    end

    def propertyDescriptor_ name, obj, type, description: nil, subtype: nil
      description = DEBUGGER__.safe_inspect(obj, short: true) if description.nil?
      oid = rand.to_s
      @obj_map[oid] = obj
      prop = {
        name: name,
        value: {
          type: type,
          description: description,
          value: obj,
          objectId: oid
        },
        configurable: true, # TODO: Change these parts because
        enumerable: true    #       they are not necessarily `true`.
      }

      if type == 'object'
        v = prop[:value]
        v.delete :value
        v[:subtype] = subtype if subtype
        v[:className] = (klass = M_CLASS.bind_call(obj)).name || klass.to_s
      end
      prop
    end

    def preview_ value, hash, overflow
      # The reason for not using "map" method is to prevent the object overriding it from causing bugs.
      # https://github.com/ruby/debug/issues/781
      props = []
      hash.each{|k, v|
        pd = propertyDescriptor k, v
        props << {
          name: pd[:name],
          type: pd[:value][:type],
          value: pd[:value][:description]
        }
      }
      {
        type: value[:type],
        subtype: value[:subtype],
        description: value[:description],
        overflow: overflow,
        properties: props
      }
    end

    def variable name, obj
      pd = propertyDescriptor name, obj
      case obj
      when Array
        pd[:value][:preview] = preview name, obj
        obj.each_with_index{|item, idx|
          if valuePreview = preview(idx.to_s, item)
            pd[:value][:preview][:properties][idx][:valuePreview] = valuePreview
          end
        }
      when Hash
        pd[:value][:preview] = preview name, obj
        obj.each_with_index{|item, idx|
          key, val = item
          if valuePreview = preview(key, val)
            pd[:value][:preview][:properties][idx][:valuePreview] = valuePreview
          end
        }
      end
      pd
    end

    def preview name, obj
      case obj
      when Array
        pd = propertyDescriptor name, obj
        overflow = false
        if obj.size > 100
          obj = obj[0..99]
          overflow = true
        end
        hash = obj.each_with_index.to_h{|o, i| [i.to_s, o]}
        preview_ pd[:value], hash, overflow
      when Hash
        pd = propertyDescriptor name, obj
        overflow = false
        if obj.size > 100
          obj = obj.to_a[0..99].to_h
          overflow = true
        end
        preview_ pd[:value], obj, overflow
      else
        nil
      end
    end

    def propertyDescriptor name, obj
      case obj
      when Array
        propertyDescriptor_ name, obj, 'object', subtype: 'array'
      when Hash
        propertyDescriptor_ name, obj, 'object', subtype: 'map'
      when String
        propertyDescriptor_ name, obj, 'string', description: obj
      when TrueClass, FalseClass
        propertyDescriptor_ name, obj, 'boolean'
      when Symbol
        propertyDescriptor_ name, obj, 'symbol'
      when Integer, Float
        propertyDescriptor_ name, obj, 'number'
      when Exception
        bt = ''
        if log = obj.backtrace_locations
          log.each do |loc|
            break if loc.path == __FILE__
            bt += "    #{loc}\n"
          end
        end
        propertyDescriptor_ name, obj, 'object', description: "#{obj.inspect}\n#{bt}", subtype: 'error'
      else
        propertyDescriptor_ name, obj, 'object'
      end
    end
  end
end
