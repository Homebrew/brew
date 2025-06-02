# frozen_string_literal: true

require 'json'
require 'irb/completion'
require 'tmpdir'
require 'fileutils'

module DEBUGGER__
  module UI_DAP
    SHOW_PROTOCOL = ENV['DEBUG_DAP_SHOW_PROTOCOL'] == '1' || ENV['RUBY_DEBUG_DAP_SHOW_PROTOCOL'] == '1'

    def self.setup debug_port
      if File.directory? '.vscode'
        dir = Dir.pwd
      else
        dir = Dir.mktmpdir("ruby-debug-vscode-")
        tempdir = true
      end

      at_exit do
        CONFIG.skip_all
        FileUtils.rm_rf dir if tempdir
      end

      key = rand.to_s

      Dir.chdir(dir) do
        Dir.mkdir('.vscode') if tempdir

        # vscode-rdbg 0.0.9 or later is needed
        open('.vscode/rdbg_autoattach.json', 'w') do |f|
          f.puts JSON.pretty_generate({
            type: "rdbg",
            name: "Attach with rdbg",
            request: "attach",
            rdbgPath: File.expand_path('../../exe/rdbg', __dir__),
            debugPort: debug_port,
            localfs: true,
            autoAttach: key,
          })
        end
      end

      cmds = ['code', "#{dir}/"]
      cmdline = cmds.join(' ')
      ssh_cmdline = "code --remote ssh-remote+[SSH hostname] #{dir}/"

      STDERR.puts "Launching: #{cmdline}"
      env = ENV.delete_if{|k, h| /RUBY/ =~ k}.to_h
      env['RUBY_DEBUG_AUTOATTACH'] = key

      unless system(env, *cmds)
        DEBUGGER__.warn <<~MESSAGE
        Can not invoke the command.
        Use the command-line on your terminal (with modification if you need).

          #{cmdline}

        If your application is running on a SSH remote host, please try:

          #{ssh_cmdline}

        MESSAGE
      end
    end

    def show_protocol dir, msg
      if SHOW_PROTOCOL
        $stderr.puts "\##{Process.pid}:[#{dir}] #{msg}"
      end
    end

    # true: all localfs
    # Array: part of localfs
    # nil: no localfs
    @local_fs_map = nil

    def self.remote_to_local_path path
      case @local_fs_map
      when nil
        nil
      when true
        path
      else # Array
        @local_fs_map.each do |(remote_path_prefix, local_path_prefix)|
          if path.start_with? remote_path_prefix
            return path.sub(remote_path_prefix){ local_path_prefix }
          end
        end

        nil
      end
    end

    def self.local_to_remote_path path
      case @local_fs_map
      when nil
        nil
      when true
        path
      else # Array
        @local_fs_map.each do |(remote_path_prefix, local_path_prefix)|
          if path.start_with? local_path_prefix
            return path.sub(local_path_prefix){ remote_path_prefix }
          end
        end

        nil
      end
    end

    def self.local_fs_map_set map
      return if @local_fs_map # already setup

      case map
      when String
        @local_fs_map = map.split(',').map{|e| e.split(':').map{|path| path.delete_suffix('/') + '/'}}
      when true
        @local_fs_map = map
      when nil
        @local_fs_map = CONFIG[:local_fs_map]
      end
    end

    def dap_setup bytes
      CONFIG.set_config no_color: true
      @seq = 0

      case self
      when UI_UnixDomainServer
        UI_DAP.local_fs_map_set true
      when UI_TcpServer
        # TODO: loopback address can be used to connect other FS env, like Docker containers
        # UI_DAP.local_fs_set if @local_addr.ipv4_loopback? || @local_addr.ipv6_loopback?
      end

      show_protocol :>, bytes
      req = JSON.load(bytes)

      # capability
      send_response(req,
             ## Supported
             supportsConfigurationDoneRequest: true,
             supportsFunctionBreakpoints: true,
             supportsConditionalBreakpoints: true,
             supportTerminateDebuggee: true,
             supportsTerminateRequest: true,
             exceptionBreakpointFilters: [
               {
                 filter: 'any',
                 label: 'rescue any exception',
                 supportsCondition: true,
                 #conditionDescription: '',
               },
               {
                 filter: 'RuntimeError',
                 label: 'rescue RuntimeError',
                 supportsCondition: true,
                 #conditionDescription: '',
               },
             ],
             supportsExceptionFilterOptions: true,
             supportsStepBack: true,
             supportsEvaluateForHovers: true,
             supportsCompletionsRequest: true,

             ## Will be supported
             # supportsExceptionOptions: true,
             # supportsHitConditionalBreakpoints:
             # supportsSetVariable: true,
             # supportSuspendDebuggee:
             # supportsLogPoints:
             # supportsLoadedSourcesRequest:
             # supportsDataBreakpoints:
             # supportsBreakpointLocationsRequest:

             ## Possible?
             # supportsRestartFrame:
             # completionTriggerCharacters:
             # supportsModulesRequest:
             # additionalModuleColumns:
             # supportedChecksumAlgorithms:
             # supportsRestartRequest:
             # supportsValueFormattingOptions:
             # supportsExceptionInfoRequest:
             # supportsDelayedStackTraceLoading:
             # supportsTerminateThreadsRequest:
             # supportsSetExpression:
             # supportsClipboardContext:

             ## Never
             # supportsGotoTargetsRequest:
             # supportsStepInTargetsRequest:
             # supportsReadMemoryRequest:
             # supportsDisassembleRequest:
             # supportsCancelRequest:
             # supportsSteppingGranularity:
             # supportsInstructionBreakpoints:
      )
      send_event 'initialized'
    end

    def send **kw
      if sock = @sock
        kw[:seq] = @seq += 1
        str = JSON.dump(kw)
        sock.write "Content-Length: #{str.bytesize}\r\n\r\n#{str}"
        show_protocol '<', str
      end
    end

    def send_response req, success: true, message: nil, **kw
      if kw.empty?
        send type: 'response',
             command: req['command'],
             request_seq: req['seq'],
             success: success,
             message: message || (success ? 'Success' : 'Failed')
      else
        send type: 'response',
             command: req['command'],
             request_seq: req['seq'],
             success: success,
             message: message || (success ? 'Success' : 'Failed'),
             body: kw
      end
    end

    def send_event name, **kw
      if kw.empty?
        send type: 'event', event: name
      else
        send type: 'event', event: name, body: kw
      end
    end

    class RetryBecauseCantRead < Exception
    end

    def recv_request
      r = IO.select([@sock])

      @session.process_group.sync do
        raise RetryBecauseCantRead unless IO.select([@sock], nil, nil, 0)

        case header = @sock.gets
        when /Content-Length: (\d+)/
          b = @sock.read(2)
          raise b.inspect unless b == "\r\n"

          l = @sock.read(s = $1.to_i)
          show_protocol :>, l
          JSON.load(l)
        when nil
          nil
        else
          raise "unrecognized line: #{l} (#{l.size} bytes)"
        end
      end
    rescue RetryBecauseCantRead
      retry
    end

    def process
      while req = recv_request
        raise "not a request: #{req.inspect}" unless req['type'] == 'request'
        args = req.dig('arguments')

        case req['command']

        ## boot/configuration
        when 'launch'
          send_response req
          UI_DAP.local_fs_map_set req.dig('arguments', 'localfs') || req.dig('arguments', 'localfsMap')
          @is_launch = true

        when 'attach'
          send_response req
          UI_DAP.local_fs_map_set req.dig('arguments', 'localfs') || req.dig('arguments', 'localfsMap')
          @is_launch = false

        when 'configurationDone'
          send_response req

          if @is_launch
            @q_msg << 'continue'
          else
            if SESSION.in_subsession?
              send_event 'stopped', reason: 'pause',
                                    threadId: 1, # maybe ...
                                    allThreadsStopped: true
            end
          end

        when 'setBreakpoints'
          req_path = args.dig('source', 'path')
          path = UI_DAP.local_to_remote_path(req_path)

          if path
            SESSION.clear_line_breakpoints path

            bps = []
            args['breakpoints'].each{|bp|
              line = bp['line']
              if cond = bp['condition']
                bps << SESSION.add_line_breakpoint(path, line, cond: cond)
              else
                bps << SESSION.add_line_breakpoint(path, line)
              end
            }
            send_response req, breakpoints: (bps.map do |bp| {verified: true,} end)
          else
            send_response req, success: false, message: "#{req_path} is not available"
          end

        when 'setFunctionBreakpoints'
          send_response req

        when 'setExceptionBreakpoints'
          process_filter = ->(filter_id, cond = nil) {
            bp =
              case filter_id
              when 'any'
                SESSION.add_catch_breakpoint 'Exception', cond: cond
              when 'RuntimeError'
                SESSION.add_catch_breakpoint 'RuntimeError', cond: cond
              else
                nil
              end
              {
                verified: !bp.nil?,
                message: bp.inspect,
              }
            }

            SESSION.clear_catch_breakpoints 'Exception', 'RuntimeError'

            filters = args.fetch('filters').map {|filter_id|
              process_filter.call(filter_id)
            }

            filters += args.fetch('filterOptions', {}).map{|bp_info|
            process_filter.call(bp_info['filterId'], bp_info['condition'])
          }

          send_response req, breakpoints: filters

        when 'disconnect'
          terminate = args.fetch("terminateDebuggee", false)

          SESSION.clear_all_breakpoints
          send_response req

          if SESSION.in_subsession?
            if terminate
              @q_msg << 'kill!'
            else
              @q_msg << 'continue'
            end
          else
            if terminate
              @q_msg << 'kill!'
              pause
            end
          end

        ## control
        when 'continue'
          @q_msg << 'c'
          send_response req, allThreadsContinued: true
        when 'next'
          begin
            @session.check_postmortem
            @q_msg << 'n'
            send_response req
          rescue PostmortemError
            send_response req,
                          success: false, message: 'postmortem mode',
                          result: "'Next' is not supported while postmortem mode"
          end
        when 'stepIn'
          begin
            @session.check_postmortem
            @q_msg << 's'
            send_response req
          rescue PostmortemError
            send_response req,
                          success: false, message: 'postmortem mode',
                          result: "'stepIn' is not supported while postmortem mode"
          end
        when 'stepOut'
          begin
            @session.check_postmortem
            @q_msg << 'fin'
            send_response req
          rescue PostmortemError
            send_response req,
                          success: false, message: 'postmortem mode',
                          result: "'stepOut' is not supported while postmortem mode"
          end
        when 'terminate'
          send_response req
          exit
        when 'pause'
          send_response req
          Process.kill(UI_ServerBase::TRAP_SIGNAL, Process.pid)
        when 'reverseContinue'
          send_response req,
                        success: false, message: 'cancelled',
                        result: "Reverse Continue is not supported. Only \"Step back\" is supported."
        when 'stepBack'
          @q_msg << req

        ## query
        when 'threads'
          send_response req, threads: SESSION.managed_thread_clients.map{|tc|
            { id: tc.id,
              name: tc.name,
            }
          }

        when 'stackTrace',
             'scopes',
             'variables',
             'evaluate',
             'source',
             'completions'
          @q_msg << req

        else
          raise "Unknown request: #{req.inspect}"
        end
      end
    ensure
      send_event :terminated unless @sock.closed?
    end

    ## called by the SESSION thread

    def respond req, res
      send_response(req, **res)
    end

    def puts result
      # STDERR.puts "puts: #{result}"
      # send_event 'output', category: 'stderr', output: "PUTS!!: " + result.to_s
    end

    def event type, *args
      case type
      when :load
        file_path, reloaded = *args

        if file_path
          send_event 'loadedSource',
                     reason: (reloaded ? :changed : :new),
                     source: {
                       path: file_path,
                     }
        end
      when :suspend_bp
        _i, bp, tid = *args
        if bp.kind_of?(CatchBreakpoint)
          reason = 'exception'
          text = bp.description
        else
          reason = 'breakpoint'
          text = bp ? bp.description : 'temporary bp'
        end

        send_event 'stopped', reason: reason,
                              description: text,
                              text: text,
                              threadId: tid,
                              allThreadsStopped: true
      when :suspend_trap
        _sig, tid = *args
        send_event 'stopped', reason: 'pause',
                              threadId: tid,
                              allThreadsStopped: true
      when :suspended
        tid, = *args
        send_event 'stopped', reason: 'step',
                              threadId: tid,
                              allThreadsStopped: true
      end
    end
  end

  class Session
    def find_waiting_tc id
      @th_clients.each{|th, tc|
        return tc if tc.id == id && tc.waiting?
      }
      return nil
    end

    def fail_response req, **kw
      @ui.respond req, success: false, **kw
      return :retry
    end

    def process_protocol_request req
      case req['command']
      when 'stepBack'
        if @tc.recorder&.can_step_back?
          request_tc [:step, :back]
        else
          fail_response req, message: 'cancelled'
        end

      when 'stackTrace'
        tid = req.dig('arguments', 'threadId')

        if tc = find_waiting_tc(tid)
          request_tc [:dap, :backtrace, req]
        else
          fail_response req
        end
      when 'scopes'
        frame_id = req.dig('arguments', 'frameId')
        if @frame_map[frame_id]
          tid, fid = @frame_map[frame_id]
          if tc = find_waiting_tc(tid)
            request_tc [:dap, :scopes, req, fid]
          else
            fail_response req
          end
        else
          fail_response req
        end
      when 'variables'
        varid = req.dig('arguments', 'variablesReference')
        if ref = @var_map[varid]
          case ref[0]
          when :globals
            vars = global_variables.map do |name|
              gv = 'Not implemented yet...'
              {
                name: name,
                value: gv.inspect,
                type: (gv.class.name || gv.class.to_s),
                variablesReference: 0,
              }
            end

            @ui.respond req, {
              variables: vars,
            }
            return :retry

          when :scope
            frame_id = ref[1]
            tid, fid = @frame_map[frame_id]

            if tc = find_waiting_tc(tid)
              request_tc [:dap, :scope, req, fid]
            else
              fail_response req
            end

          when :variable
            tid, vid = ref[1], ref[2]

            if tc = find_waiting_tc(tid)
              request_tc [:dap, :variable, req, vid]
            else
              fail_response req
            end
          else
            raise "Unknown type: #{ref.inspect}"
          end
        else
          fail_response req
        end
      when 'evaluate'
        frame_id = req.dig('arguments', 'frameId')
        context = req.dig('arguments', 'context')

        if @frame_map[frame_id]
          tid, fid = @frame_map[frame_id]
          expr = req.dig('arguments', 'expression')
          if tc = find_waiting_tc(tid)
            request_tc [:dap, :evaluate, req, fid, expr, context]
          else
            fail_response req
          end
        else
          fail_response req, result: "can't evaluate"
        end
      when 'source'
        ref = req.dig('arguments', 'sourceReference')
        if src = @src_map[ref]
          @ui.respond req, content: src.join("\n")
        else
          fail_response req, message: 'not found...'
        end
        return :retry

      when 'completions'
        frame_id = req.dig('arguments', 'frameId')
        tid, fid = @frame_map[frame_id]

        if tc = find_waiting_tc(tid)
          text = req.dig('arguments', 'text')
          line = req.dig('arguments', 'line')
          if col  = req.dig('arguments', 'column')
            text = text.split(/\n/)[line.to_i - 1][0...(col.to_i - 1)]
          end
          request_tc [:dap, :completions, req, fid, text]
        else
          fail_response req
        end
      else
        raise "Unknown DAP request: #{req.inspect}"
      end
    end

    def dap_event args
      # puts({dap_event: args}.inspect)
      type, req, result = args

      case type
      when :backtrace
        result[:stackFrames].each{|fi|
          frame_depth = fi[:id]
          fi[:id] = id = @frame_map.size + 1
          @frame_map[id] = [req.dig('arguments', 'threadId'), frame_depth]
          if fi[:source]
            if src = fi[:source][:sourceReference]
              src_id = @src_map.size + 1
              @src_map[src_id] = src
              fi[:source][:sourceReference] = src_id
            else
              fi[:source][:sourceReference] = 0
            end
          end
        }
        @ui.respond req, result
      when :scopes
        frame_id = req.dig('arguments', 'frameId')
        local_scope = result[:scopes].first
        local_scope[:variablesReference] = id = @var_map.size + 1

        @var_map[id] = [:scope, frame_id]
        @ui.respond req, result
      when :scope
        tid = result.delete :tid
        register_vars result[:variables], tid
        @ui.respond req, result
      when :variable
        tid = result.delete :tid
        register_vars result[:variables], tid
        @ui.respond req, result
      when :evaluate
        message = result.delete :message
        if message
          @ui.respond req, success: false, message: message
        else
          tid = result.delete :tid
          register_var result, tid
          @ui.respond req, result
        end
      when :completions
        @ui.respond req, result
      else
        raise "unsupported: #{args.inspect}"
      end
    end

    def register_var v, tid
      if (tl_vid = v[:variablesReference]) > 0
        vid = @var_map.size + 1
        @var_map[vid] = [:variable, tid, tl_vid]
        v[:variablesReference] = vid
      end
    end

    def register_vars vars, tid
      raise tid.inspect unless tid.kind_of?(Integer)
      vars.each{|v|
        register_var v, tid
      }
    end
  end

  class ThreadClient
    def value_inspect obj
      # TODO: max length should be configuarable?
      DEBUGGER__.safe_inspect obj, short: true, max_length: 4 * 1024
    end

    def process_dap args
      # pp tc: self, args: args
      type = args.shift
      req = args.shift

      case type
      when :backtrace
        start_frame = req.dig('arguments', 'startFrame') || 0
        levels = req.dig('arguments', 'levels') || 1_000
        frames = []
        @target_frames.each_with_index do |frame, i|
          next if i < start_frame
          break if (levels -= 1) < 0

          path = frame.realpath || frame.path
          source_name = path ? File.basename(path) : frame.location.to_s

          if (path && File.exist?(path)) && (local_path = UI_DAP.remote_to_local_path(path))
            # ok
          else
            ref = frame.file_lines
          end

          frames << {
            id: i, # id is refilled by SESSION
            name: frame.name,
            line: frame.location.lineno,
            column: 1,
            source: {
              name: source_name,
              path: (local_path || path),
              sourceReference: ref,
            },
          }
        end

        event! :dap_result, :backtrace, req, {
          stackFrames: frames,
          totalFrames: @target_frames.size,
        }
      when :scopes
        fid = args.shift
        frame = get_frame(fid)

        lnum =
          if frame.binding
            frame.binding.local_variables.size
          elsif vars = frame.local_variables
            vars.size
          else
            0
          end

        event! :dap_result, :scopes, req, scopes: [{
          name: 'Local variables',
          presentationHint: 'locals',
          # variablesReference: N, # filled by SESSION
          namedVariables: lnum,
          indexedVariables: 0,
          expensive: false,
        }, {
          name: 'Global variables',
          presentationHint: 'globals',
          variablesReference: 1, # GLOBAL
          namedVariables: global_variables.size,
          indexedVariables: 0,
          expensive: false,
        }]
      when :scope
        fid = args.shift
        frame = get_frame(fid)
        vars = collect_locals(frame).map do |var, val|
          variable(var, val)
        end

        event! :dap_result, :scope, req, variables: vars, tid: self.id
      when :variable
        vid = args.shift
        obj = @var_map[vid]
        if obj
          case req.dig('arguments', 'filter')
          when 'indexed'
            start = req.dig('arguments', 'start') || 0
            count = req.dig('arguments', 'count') || obj.size
            vars = (start ... (start + count)).map{|i|
              variable(i.to_s, obj[i])
            }
          else
            vars = []

            case obj
            when Hash
              vars = obj.map{|k, v|
                variable(value_inspect(k), v,)
              }
            when Struct
              vars = obj.members.map{|m|
                variable(m, obj[m])
              }
            when String
              vars = [
                variable('#length', obj.length),
                variable('#encoding', obj.encoding)
              ]
            when Class, Module
              vars = obj.instance_variables.map{|iv|
                variable(iv, obj.instance_variable_get(iv))
              }
              vars.unshift variable('%ancestors', obj.ancestors[1..])
            when Range
              vars = [
                variable('#begin', obj.begin),
                variable('#end', obj.end),
              ]
            end

            vars += M_INSTANCE_VARIABLES.bind_call(obj).map{|iv|
              variable(iv, M_INSTANCE_VARIABLE_GET.bind_call(obj, iv))
            }
            vars.unshift variable('#class', M_CLASS.bind_call(obj))
          end
        end
        event! :dap_result, :variable, req, variables: (vars || []), tid: self.id

      when :evaluate
        fid, expr, context = args
        frame = get_frame(fid)
        message = nil

        if frame && (b = frame.eval_binding)
          special_local_variables frame do |name, var|
            b.local_variable_set(name, var) if /\%/ !~ name
          end

          case context
          when 'repl', 'watch'
            begin
              result = b.eval(expr.to_s, '(DEBUG CONSOLE)')
            rescue Exception => e
              result = e
            end

          when 'hover'
            case expr
            when /\A\@\S/
              begin
                result = M_INSTANCE_VARIABLE_GET.bind_call(b.receiver, expr)
              rescue NameError
                message = "Error: Not defined instance variable: #{expr.inspect}"
              end
            when /\A\$\S/
              global_variables.each{|gvar|
                if gvar.to_s == expr
                  result = eval(gvar.to_s)
                  break false
                end
              } and (message = "Error: Not defined global variable: #{expr.inspect}")
            when /\Aself$/
              result = b.receiver
            when /(\A((::[A-Z]|[A-Z])\w*)+)/
              unless result = search_const(b, $1)
                message = "Error: Not defined constants: #{expr.inspect}"
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
          else
            message = "Error: unknown context: #{context}"
          end
        else
          result = 'Error: Can not evaluate on this frame'
        end

        event! :dap_result, :evaluate, req, message: message, tid: self.id, **evaluate_result(result)

      when :completions
        fid, text = args
        frame = get_frame(fid)

        if (b = frame&.binding) && word = text&.split(/[\s\{]/)&.last
          words = IRB::InputCompletor::retrieve_completion_data(word, bind: b).compact
        end

        event! :dap_result, :completions, req, targets: (words || []).map{|phrase|
          detail = nil

          if /\b([_a-zA-Z]\w*[!\?]?)\z/ =~ phrase
            w = $1
          else
            w = phrase
          end

          begin
            v = b.local_variable_get(w)
            detail ="(variable: #{value_inspect(v)})"
          rescue NameError
          end

          {
            label: phrase,
            text: w,
            detail: detail,
          }
        }

      else
        raise "Unknown req: #{args.inspect}"
      end
    end

    def search_const b, expr
      cs = expr.delete_prefix('::').split('::')
      [Object, *b.eval('::Module.nesting')].reverse_each{|mod|
        if cs.all?{|c|
             if mod.const_defined?(c)
               mod = mod.const_get(c)
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
      v.delete :name
      v.delete :value
      v[:result] = value_inspect(r)
      v
    end

    def variable_ name, obj, indexedVariables: 0, namedVariables: 0
      if indexedVariables > 0 || namedVariables > 0
        vid = @var_map.size + 1
        @var_map[vid] = obj
      else
        vid = 0
      end

      ivnum = M_INSTANCE_VARIABLES.bind_call(obj).size

      { name: name,
        value: value_inspect(obj),
        type: (klass = M_CLASS.bind_call(obj)).name || klass.to_s,
        variablesReference: vid,
        indexedVariables: indexedVariables,
        namedVariables: namedVariables + ivnum,
      }
    end

    def variable name, obj
      case obj
      when Array
        variable_ name, obj, indexedVariables: obj.size
      when Hash
        variable_ name, obj, namedVariables: obj.size
      when String
        variable_ name, obj, namedVariables: 3 # #to_str, #length, #encoding
      when Struct
        variable_ name, obj, namedVariables: obj.size
      when Class, Module
        variable_ name, obj, namedVariables: 1 # %ancestors (#ancestors without self)
      when Range
        variable_ name, obj, namedVariables: 2 # #begin, #end
      else
        variable_ name, obj, namedVariables: 1 # #class
      end
    end
  end
end
