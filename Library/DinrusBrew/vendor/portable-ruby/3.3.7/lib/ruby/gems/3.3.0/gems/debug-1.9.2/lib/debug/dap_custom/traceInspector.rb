module DEBUGGER__
  module DAP_TraceInspector
    class MultiTracer < Tracer
      def initialize ui, evts, trace_params, max_log_size: nil, **kw
        @evts = evts
        @log = []
        @trace_params = trace_params
        if max_log_size
          @max_log_size = max_log_size
        else
          @max_log_size = 50000
        end
        @dropped_trace_cnt = 0
        super(ui, **kw)
        @type = 'multi'
        @name = 'TraceInspector'
      end
  
      attr_accessor :dropped_trace_cnt
      attr_reader :log
  
      def setup
        @tracer = TracePoint.new(*@evts){|tp|
          next if skip?(tp)
  
          case tp.event
          when :call, :c_call, :b_call
            if @trace_params
              params = parameters_info tp
            end
            append(call_trace_log(tp, params: params))
          when :return, :c_return, :b_return
            return_str = DEBUGGER__.safe_inspect(tp.return_value, short: true, max_length: 4096)
            append(call_trace_log(tp, return_str: return_str))
          when :line
            append(line_trace_log(tp))
          end
        }
      end

      def parameters_info tp
        b = tp.binding
        tp.parameters.map{|_type, name|
          begin
            { name: name, value: DEBUGGER__.safe_inspect(b.local_variable_get(name), short: true, max_length: 4096) }
          rescue NameError, TypeError
            nil
          end
        }.compact
      end
  
      def call_identifier_str tp
        if tp.defined_class
          minfo(tp)
        else
          "block"
        end
      end
  
      def append log
        if @log.size >= @max_log_size
          @dropped_trace_cnt += 1
          @log.shift
        end
        @log << log
      end
  
      def call_trace_log tp, return_str: nil, params: nil
        log = {
          depth: DEBUGGER__.frame_depth,
          name: call_identifier_str(tp),
          threadId: Thread.current.instance_variable_get(:@__thread_client_id),
          location: {
            path: tp.path,
            line: tp.lineno
          }
        }
        log[:returnValue] = return_str if return_str
        log[:parameters] = params if params && params.size > 0
        log
      end
  
      def line_trace_log tp
        {
          depth: DEBUGGER__.frame_depth,
          threadId: Thread.current.instance_variable_get(:@__thread_client_id),
          location: {
            path: tp.path,
            line: tp.lineno
          }
        }
      end
  
      def skip? tp
        super || !@evts.include?(tp.event)
      end

      def skip_with_pattern?(tp)
        super && !tp.method_id&.match?(@pattern)
      end
    end

    class Custom_Recorder < ThreadClient::Recorder
      def initialize max_log_size: nil
        if max_log_size
          @max_log_size = max_log_size
        else
          @max_log_size = 50000
        end
        @dropped_trace_cnt = 0
        super()
      end

      attr_accessor :dropped_trace_cnt

      def append frames
        if @log.size >= @max_log_size
          @dropped_trace_cnt += 1
          @log.shift
        end
        @log << frames
      end
    end

    module Custom_UI_DAP
      def custom_dap_request_rdbgTraceInspector(req)
        @q_msg << req
      end
    end

    module Custom_Session
      def process_trace_cmd req
        cmd = req.dig('arguments', 'subCommand')
        case cmd
        when 'enable'
          events = req.dig('arguments', 'events')
          evts = []
          trace_params = false
          filter = req.dig('arguments', 'filterRegExp')
          max_log_size = req.dig('arguments', 'maxLogSize')
          events.each{|evt|
            case evt
            when 'traceLine'
              evts << :line
            when 'traceCall'
              evts << :call
              evts << :b_call
            when 'traceReturn'
              evts << :return
              evts << :b_return
            when 'traceParams'
              trace_params = true
            when 'traceClanguageCall'
              evts << :c_call
            when 'traceClanguageReturn'
              evts << :c_return
            else
              raise "unknown trace type #{evt}"
            end
          }
          add_tracer MultiTracer.new @ui, evts, trace_params, max_log_size: max_log_size, pattern: filter
          @ui.respond req, {}
        when 'disable'
          if t = find_multi_trace
            t.disable
          end
          @ui.respond req, {}
        when 'collect'
          logs = []
          if t = find_multi_trace
            logs = t.log
            if t.dropped_trace_cnt > 0
              @ui.puts "Return #{logs.size} traces and #{t.dropped_trace_cnt} traces are dropped"
            else
              @ui.puts "Return #{logs.size} traces"
            end
            t.dropped_trace_cnt = 0
          end
          @ui.respond req, logs: logs
        else
          raise "Unknown trace sub command #{cmd}"
        end
        return :retry
      end

      def find_multi_trace
        @tracers.values.each{|t|
          if t.type == 'multi'
            return t
          end
        }
        return nil
      end

      def process_record_cmd req
        cmd = req.dig('arguments', 'subCommand')
        case cmd
        when 'enable'
          @tc << [:dap, :rdbgTraceInspector, req]
        when 'disable'
          @tc << [:dap, :rdbgTraceInspector, req]
        when 'step'
          tid = req.dig('arguments', 'threadId')
          count = req.dig('arguments', 'count')
          if tc = find_waiting_tc(tid)
            @ui.respond req, {}
            tc << [:step, :in, count]
          else
            fail_response req
          end
        when 'stepBack'
          tid = req.dig('arguments', 'threadId')
          count = req.dig('arguments', 'count')
          if tc = find_waiting_tc(tid)
            @ui.respond req, {}
            tc << [:step, :back, count]
          else
            fail_response req
          end
        when 'collect'
          tid = req.dig('arguments', 'threadId')
          if tc = find_waiting_tc(tid)
            tc << [:dap, :rdbgTraceInspector, req]
          else
            fail_response req
          end
        else
          raise "Unknown record sub command #{cmd}"
        end
      end

      def custom_dap_request_rdbgTraceInspector(req)
        cmd = req.dig('arguments', 'command')
        case cmd
        when 'trace'
          process_trace_cmd req
        when 'record'
          process_record_cmd req
        else
          raise "Unknown command #{cmd}"
        end
      end

      def custom_dap_request_event_rdbgTraceInspector(req, result)
        cmd = req.dig('arguments', 'command')
        case cmd
        when 'record'
          process_event_record_cmd(req, result)
        else
          raise "Unknown command #{cmd}"
        end
      end

      def process_event_record_cmd(req, result)
        cmd = req.dig('arguments', 'subCommand')
        case cmd
        when 'enable'
          @ui.respond req, {}
        when 'disable'
          @ui.respond req, {}
        when 'collect'
          cnt = result.delete :dropped_trace_cnt
          if cnt > 0
            @ui.puts "Return #{result[:logs].size} traces and #{cnt} traces are dropped"
          else
            @ui.puts "Return #{result[:logs].size} traces"
          end
          @ui.respond req, result
        else
          raise "Unknown command #{cmd}"
        end
      end
    end

    module Custom_ThreadClient
      def custom_dap_request_rdbgTraceInspector(req)
        cmd = req.dig('arguments', 'command')
        case cmd
        when 'record'
          process_record_cmd(req)
        else
          raise "Unknown command #{cmd}"
        end
      end

      def process_record_cmd(req)
        cmd = req.dig('arguments', 'subCommand')
        case cmd
        when 'enable'
          size = req.dig('arguments', 'maxLogSize')
          @recorder = Custom_Recorder.new max_log_size: size
          @recorder.enable
          event! :protocol_result, :rdbgTraceInspector, req
        when 'disable'
          if @recorder&.enabled?
            @recorder.disable
          end
          @recorder = nil
          event! :protocol_result, :rdbgTraceInspector, req
        when 'collect'
          logs = []
          log_index = nil
          trace_cnt = 0
          unless @recorder.nil?
            log_index = @recorder.log_index
            @recorder.log.each{|frames|
              crt_frame = frames[0]
              log = {
                name: crt_frame.name,
                location: {
                  path: crt_frame.location.path,
                  line: crt_frame.location.lineno,
                },
                depth: crt_frame.frame_depth
              }
              if params = crt_frame.iseq_parameters_info
                log[:parameters] = params
              end
              if return_str = crt_frame.return_str
                log[:returnValue] = return_str
              end
              logs << log
            }
            trace_cnt = @recorder.dropped_trace_cnt
            @recorder.dropped_trace_cnt = 0
          end
          event! :protocol_result, :rdbgTraceInspector, req, logs: logs, stoppedIndex: log_index, dropped_trace_cnt: trace_cnt
        else
          raise "Unknown command #{cmd}"
        end
      end
    end

    ::DEBUGGER__::SESSION.extend_feature session: Custom_Session, thread_client: Custom_ThreadClient, ui: Custom_UI_DAP
  end
end
