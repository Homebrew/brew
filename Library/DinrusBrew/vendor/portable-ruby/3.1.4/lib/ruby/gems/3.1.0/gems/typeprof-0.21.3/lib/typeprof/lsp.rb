require "socket"
require "json"
require "uri"

module TypeProf
  def self.start_lsp_server(config)
    if config.lsp_options[:stdio]
      $stdin.binmode
      $stdout.binmode
      reader = LSP::Reader.new($stdin)
      writer = LSP::Writer.new($stdout)
      # pipe all builtin print output to stderr to avoid conflicting with lsp
      $stdout = $stderr
      TypeProf::LSP::Server.new(config, reader, writer).run
    else
      Socket.tcp_server_sockets("localhost", config.lsp_options[:port]) do |servs|
        serv = servs[0].local_address
        $stdout << JSON.generate({
          host: serv.ip_address,
          port: serv.ip_port,
          pid: $$,
        })
        $stdout.flush

        $stdout = $stderr

        Socket.accept_loop(servs) do |sock|
          sock.set_encoding("UTF-8")
          begin
            reader = LSP::Reader.new(sock)
            writer = LSP::Writer.new(sock)
            TypeProf::LSP::Server.new(config, reader, writer).run
          ensure
            sock.close
          end
          exit
        end
      end
    end
  end

  module LSP
    CompletionSession = Struct.new(:results, :row, :start_col_offset)
    class CompletionSession
      def reusable?(other_row, other_start_col_offset)
        other_row == self.row && other_start_col_offset == self.start_col_offset
      end
    end

    class Text
      class AnalysisToken < Utils::CancelToken
        def initialize
          @timer = Utils::TimerCancelToken.new(1)
          @cancelled = false
        end

        def cancel
          @cancelled = true
        end

        def cancelled?
          @timer.cancelled? || @cancelled
        end
      end

      def initialize(server, uri, text, version)
        @server = server
        @uri = uri
        @text = text
        @version = version
        @sigs = nil

        @last_analysis_cancel_token = nil
        @analysis_queue = Queue.new
        @analysis_thread = Thread.new do
          loop do
            work = @analysis_queue.pop
            begin
              work.call
            rescue Exception
              puts "Rescued exception:"
              puts $!.full_message
              puts
            end
          end
        end

        # analyze synchronously to respond the first codeLens request
        res, def_table, caller_table = self.analyze(uri, text)
        on_text_changed_analysis(res, def_table, caller_table)
      end

      attr_reader :text, :version, :sigs, :caller_table
      attr_accessor :definition_table

      def lines
        @text.lines
      end

      def apply_changes(changes, version)
        @definition_table = nil
        text = @text.empty? ? [] : @text.lines
        changes.each do |change|
          case change
          in {
            range: {
                start: { line: start_row, character: start_col },
                end:   { line: end_row  , character: end_col   }
            },
            text: change_text,
          }
          else
            raise
          end
          text << "" if start_row == text.size
          text << "" if end_row == text.size
          if start_row == end_row
            text[start_row][start_col...end_col] = change_text
          else
            text[start_row][start_col..] = ""
            text[end_row][...end_col] = ""
            change_text = change_text.lines
            case change_text.size
            when 0
              text[start_row] += text[end_row]
              text[start_row + 1 .. end_row] = []
            when 1
              text[start_row] += change_text.first + text[end_row]
              text[start_row + 1 .. end_row] = []
            else
              text[start_row] += change_text.shift
              text[end_row].prepend(change_text.pop)
              text[start_row + 1 ... end_row - 1] = change_text
            end
          end
        end
        @text = text.join
        @version = version

        on_text_changed
      end

      def new_code_completion_session(row, start_offset, end_offset)
        lines = @text.lines
        lines[row][start_offset, end_offset] = ".__typeprof_lsp_completion"
        tmp_text = lines.join
        res, = analyze(@uri, tmp_text)
        if res && res[:completion]
          results = res[:completion].keys.map do |name|
            {
              label: name,
              kind: 2, # Method
            }
          end
          return CompletionSession.new(results, row, start_offset)
        else
          nil
        end
      end

      def code_complete(loc, trigger_kind)
        case loc
        in { line: row, character: col }
        end
        unless row < @text.lines.length && col >= 1 && @text.lines[row][0, col] =~ /\.\w*$/
          return nil
        end
        start_offset = $~.begin(0)
        end_offset = $&.size

        case trigger_kind
        when LSP::CompletionTriggerKind::TRIGGER_FOR_INCOMPLETE_COMPLETIONS
          unless @current_completion_session&.reusable?(row, start_offset)
            puts "no reusable completion session but got TRIGGER_FOR_INCOMPLETE_COMPLETIONS"
            @current_completion_session = new_code_completion_session(row, start_offset, end_offset)
          end
          return @current_completion_session.results
        else
          @current_completion_session = new_code_completion_session(row, start_offset, end_offset)
          return @current_completion_session&.results
        end
      end

      private def locate_arg_index_in_signature_help(node, loc, sig_help)
        case node.type
        when :FCALL
          _mid, args_node = node.children
        when :CALL
          _recv, _mid, args_node = node.children
        end

        idx = 0

        if args_node
          arg_nodes = args_node.children.compact

          arg_indexes = {}
          hash = arg_nodes.pop if arg_nodes.last&.type == :HASH

          arg_nodes.each_with_index do |node, i|
            # Ingore arguments after rest argument
            break if node.type == :LIST || node.type == :ARGSCAT

            arg_indexes[i] = ISeq.code_range_from_node(node)
          end

          # Handle keyword arguments
          if hash
            hash.children.last.children.compact.each_slice(2) do |node1, node2|
              # key:  expression
              # ^^^^  ^^^^^^^^^^
              # node1 node2
              key = node1.children.first
              arg_indexes[key] =
                CodeRange.new(
                  CodeLocation.new(node1.first_lineno, node1.first_lineno),
                  CodeLocation.new(node2.last_lineno, node2.last_lineno),
                )
            end
          end

          if arg_indexes.size >= 1 && arg_indexes.values.last.last < loc
            # There is the cursor after the last argument: "foo(111, 222,|)"
            idx = arg_indexes.size - 1
            prev_cr = arg_indexes.values.last
            if prev_cr.last.lineno == loc.lineno
              line = @text.lines[prev_cr.last.lineno - 1]
              idx += 1 if line[prev_cr.last.column..loc.column].include?(",")
            end
          else
            # There is the cursor within any argument: "foo(111,|222)" or foo(111, 22|2)"
            prev_cr = nil
            arg_indexes.each do |i, cr|
              idx = sig_help.keys.index(i)
              if loc < cr.first
                break if !prev_cr || prev_cr.last.lineno != loc.lineno
                line = @text.lines[prev_cr.last.lineno - 1]
                idx -= 1 unless line[prev_cr.last.column..loc.column].include?(",")
                break
              end
              break if loc <= cr.last
              prev_cr = cr
            end
          end
        end

        idx
      end

      def signature_help(loc, trigger_kind)
        loc = CodeLocation.from_lsp(loc)

        res, = analyze(@uri, @text, signature_help_loc: loc)

        if res
          res[:signature_help].filter_map do |sig_str, sig_help, node_id|
            node = ISeq.find_node_by_id(@text, node_id)
            if node && ISeq.code_range_from_node(node).contain_loc?(loc)
              idx = locate_arg_index_in_signature_help(node, loc, sig_help)

              {
                label: sig_str,
                parameters: sig_help.values.map do |r|
                  {
                    label: [r.begin, r.end],
                  }
                end,
                activeParameter: idx,
              }
            end
          end
        else
          nil
        end
      end

      def analyze(uri, text, cancel_token: nil, signature_help_loc: nil)
        config = @server.typeprof_config.dup
        path = URI(uri).path
        config.rb_files = [[path, text]]
        config.rbs_files = ["typeprof.rbs"] # XXX
        config.verbose = 0
        config.max_sec = 1
        config.options[:show_errors] = true
        config.options[:show_indicator] = false
        config.options[:lsp] = true
        config.options[:signature_help_loc] = [path, signature_help_loc] if signature_help_loc

        TypeProf.analyze(config, cancel_token)
      rescue SyntaxError
      end

      def push_analysis_queue(&work)
        @analysis_queue.push(work)
      end

      def on_text_changed
        cancel_token = AnalysisToken.new
        @last_analysis_cancel_token&.cancel
        @last_analysis_cancel_token = cancel_token

        uri = @uri
        text = @text
        self.push_analysis_queue do
          if cancel_token.cancelled?
            next
          end
          res, def_table, caller_table = self.analyze(uri, text, cancel_token: cancel_token)
          unless cancel_token.cancelled?
            on_text_changed_analysis(res, def_table, caller_table)
          end
        end
      end

      def on_text_changed_analysis(res, definition_table, caller_table)
        @definition_table = definition_table
        @caller_table = caller_table
        return unless res

        @sigs = []
        res[:sigs].each do |file, lineno, sig_str, rbs_code_range, class_kind, class_name|
          uri0 = "file://" + file
          if @uri == uri0
            command = { title: sig_str }
            if rbs_code_range
              command[:command] = "typeprof.jumpToRBS"
              command[:arguments] = [uri0, { line: lineno - 1, character: 0 }, @server.root_uri + "/" + rbs_code_range[0], rbs_code_range[1].to_lsp]
            else
              command[:command] = "typeprof.createPrototypeRBS"
              command[:arguments] = [class_kind, class_name, sig_str]
            end
            @sigs << {
              range: {
                start: { line: lineno - 1, character: 0 },
                end: { line: lineno - 1, character: 1 },
              },
              command: command,
            }
          end
        end

        diagnostics = {}
        res[:errors]&.each do |(file, code_range), msg|
          next unless file and code_range
          uri0 = "file://" + file
          diagnostics[uri0] ||= []
          diagnostics[uri0] << {
            range: code_range.to_lsp,
            severity: 1,
            source: "TypeProf",
            message: msg,
          }
        end

        @server.send_request("workspace/codeLens/refresh")

        @server.send_notification(
          "textDocument/publishDiagnostics",
          {
            uri: @uri,
            version: version,
            diagnostics: diagnostics[@uri] || [],
          }
        )
      end
    end

    class Message
      def initialize(server, json)
        @server = server
        @id = json[:id]
        @method = json[:method]
        @params = json[:params]
      end

      def run
        p [:ignored, @method]
      end

      def respond(result)
        raise "do not respond to notification" if @id == nil
        @server.send_response(id: @id, result: result)
      end

      def respond_error(error)
        raise "do not respond to notification" if @id == nil
        @server.send_response(id: @id, error: error)
      end

      Classes = []
      def self.inherited(klass)
        Classes << klass
      end

      Table = Hash.new(Message)
      def self.build_table
        Classes.each {|klass| Table[klass::METHOD] = klass }
      end

      def self.find(method)
        Table[method]
      end
    end

    module ErrorCodes
      ParseError = -32700
      InvalidRequest = -32600
      MethodNotFound = -32601
      InvalidParams = -32602
      InternalError = -32603
    end

    class Message::Initialize < Message
      METHOD = "initialize"
      def run
        @server.root_uri = @params[:rootUri]
        pwd = Dir.pwd
        @params[:workspaceFolders]&.each do |folder|
          folder => { uri:, }
          if pwd == URI(uri).path
            @server.root_uri = uri
          end
        end

        respond(
          capabilities: {
            textDocumentSync: {
              openClose: true,
              change: 2, # Incremental
            },
            completionProvider: {
              triggerCharacters: ["."],
            },
            signatureHelpProvider: {
              triggerCharacters: ["(", ","],
            },
            #codeActionProvider: {
            #  codeActionKinds: ["quickfix", "refactor"],
            #  resolveProvider: false,
            #},
            codeLensProvider: {
              resolveProvider: true,
            },
            executeCommandProvider: {
              commands: [
                "typeprof.createPrototypeRBS",
                "typeprof.enableSignature",
                "typeprof.disableSignature",
              ],
            },
            definitionProvider: true,
            typeDefinitionProvider: true,
            referencesProvider: true,
          },
          serverInfo: {
            name: "typeprof",
            version: "0.0.0",
          },
        )

        puts "TypeProf for IDE is started successfully"
      end
    end

    class Message::Initialized < Message
      METHOD = "initialized"
      def run
      end
    end

    class Message::Shutdown < Message
      METHOD = "shutdown"
      def run
        respond(nil)
      end
    end

    class Message::Exit < Message
      METHOD = "exit"
      def run
        exit
      end
    end

    module Message::Workspace
    end

    class Message::Workspace::DidChangeWatchedFiles < Message
      METHOD = "workspace/didChangeWatchedFiles"
      def run
        #p "workspace/didChangeWatchedFiles"
        #pp @params
      end
    end

    class Message::Workspace::ExecuteCommand < Message
      METHOD = "workspace/executeCommand"
      def run
        case @params[:command]
        when "typeprof.enableSignature"
          @server.signature_enabled = true
          @server.send_request("workspace/codeLens/refresh")
          respond(nil)
        when "typeprof.disableSignature"
          @server.signature_enabled = false
          @server.send_request("workspace/codeLens/refresh")
          respond(nil)
        when "typeprof.createPrototypeRBS"
          class_kind, class_name, sig_str = @params[:arguments]
          code_range =
            CodeRange.new(
              CodeLocation.new(1, 0),
              CodeLocation.new(1, 0),
            )
          text = []
          text << "#{ class_kind } #{ class_name.join("::") }\n"
          text << "  #{ sig_str }\n"
          text << "end\n\n"
          text = text.join
          @server.send_request(
            "workspace/applyEdit",
            edit: {
              changes: {
                @server.root_uri + "/typeprof.rbs" => [
                  {
                    range: code_range.to_lsp,
                    newText: text,
                  }
                ],
              },
            },
          ) do |res|
            code_range =
              CodeRange.new(
                CodeLocation.new(1, 0),
                CodeLocation.new(3, 3), # 3 = "end".size
              )
            @server.send_request(
              "window/showDocument",
              uri: @server.root_uri + "/typeprof.rbs",
              takeFocus: true,
              selection: code_range.to_lsp,
            )
          end
          respond(nil)
        else
          respond_error(
            code: ErrorCodes::InvalidRequest,
            message: "Unknown command: #{ @params[:command] }",
          )
        end
      end
    end

    module Message::TextDocument
    end

    class Message::TextDocument::DidOpen < Message
      METHOD = "textDocument/didOpen"
      def run
        case @params
        in { textDocument: { uri:, version:, text: } }
        else
          raise
        end
        if uri.start_with?(@server.root_uri)
          @server.open_texts[uri] = Text.new(@server, uri, text, version)
        end
      end
    end

    class Message::TextDocument::DidChange < Message
      METHOD = "textDocument/didChange"
      def run
        case @params
        in { textDocument: { uri:, version: }, contentChanges: changes }
        else
          raise
        end
        @server.open_texts[uri]&.apply_changes(changes, version)
      end

      def cancel
        puts "cancel"
      end
    end

    class Message::TextDocument::DidClose < Message
      METHOD = "textDocument/didClose"
      def run
        case @params
          in { textDocument: { uri: } }
        else
          raise
        end
        @server.open_texts.delete(uri)
      end
    end

    class Message::TextDocument::Definition < Message
      METHOD = "textDocument/definition"
      def run
        case @params
        in {
          textDocument: { uri:, },
          position: loc,
        }
        else
          raise
        end

        definition_table = @server.open_texts[uri]&.definition_table
        code_locations = definition_table[CodeLocation.from_lsp(loc)] if definition_table
        if code_locations
          respond(
            code_locations.map do |path, code_range|
              {
                uri: "file://" + path,
                range: code_range.to_lsp,
              }
            end
          )
        else
          respond(nil)
        end
      end
    end

    class Message::TextDocument::TypeDefinition < Message
      METHOD = "textDocument/typeDefinition"
      def run
        respond(nil)
        # jump example
        #respond(
        #  uri: "file:///path/to/typeprof/vscode/sandbox/test.rbs",
        #  range: {
        #    start: { line: 1, character: 4 },
        #    end: { line: 1, character: 7 },
        #  },
        #)
      end
    end

    class Message::TextDocument::References < Message
      METHOD = "textDocument/references"
      def run
        case @params
        in {
          textDocument: { uri:, },
          position: loc,
        }
        else
          raise
        end

        caller_table = @server.open_texts[uri]&.caller_table
        code_locations = caller_table[CodeLocation.from_lsp(loc)] if caller_table
        if code_locations
          respond(
            code_locations.map do |path, code_range|
              {
                uri: "file://" + path,
                range: code_range.to_lsp,
              }
            end
          )
        else
          respond(nil)
        end
      end
    end

    module CompletionTriggerKind
      INVOKED = 1
      TRIGGER_CHARACTER = 2
      TRIGGER_FOR_INCOMPLETE_COMPLETIONS = 3
    end

    class Message::TextDocument::Completion < Message
      METHOD = "textDocument/completion"
      def run
        case @params
        in {
          textDocument: { uri:, },
          position: loc,
          context: {
            triggerKind: trigger_kind
          },
        }
        in {
          textDocument: { uri:, },
          position: loc,
        }
          trigger_kind = 1
        else
          raise
        end

        items = @server.open_texts[uri]&.code_complete(loc, trigger_kind)

        if items
          respond(
            {
              isIncomplete: true,
              items: items
            }
          )
        else
          respond(nil)
        end
      end
    end

    class Message::TextDocument::SignatureHelp < Message
      METHOD = "textDocument/signatureHelp"
      def run
        case @params
        in {
          textDocument: { uri:, },
          position: loc,
          context: {
            triggerKind: trigger_kind
          },
        }
        in {
          textDocument: { uri:, },
          position: loc,
        }
          trigger_kind = 1
        else
          raise
        end

        items = @server.open_texts[uri]&.signature_help(loc, trigger_kind)

        if items
          respond({
            signatures: items
          })
        else
          respond(nil)
        end
      end
    end

    class Message::TextDocument::CodeLens < Message
      METHOD = "textDocument/codeLens"
      def run
        case @params
          in { textDocument: { uri: } }
        else
          raise
        end

        text = @server.open_texts[uri]
        if text && @server.signature_enabled
          # enqueue in the analysis queue because codeLens is order sensitive
          text.push_analysis_queue do
            respond(text.sigs)
          end
        else
          respond(nil)
        end
      end
    end

    class Message::CancelRequest < Message
      METHOD = "$/cancelRequest"
      def run
        req = @server.running_requests_from_client[@params[:id]]
        #p [:cancel, @params[:id]]
        req.cancel if req.respond_to?(:cancel)
      end
    end

    Message.build_table

    class Reader
      class ProtocolError < StandardError
      end

      def initialize(io)
        @io = io
      end

      def read
        while line = @io.gets
          line2 = @io.gets
          if line =~ /\AContent-length: (\d+)\r\n\z/i && line2 == "\r\n"
            len = $1.to_i
            json = JSON.parse(@io.read(len), symbolize_names: true)
            yield json
          else
            raise ProtocolError, "LSP broken header"
          end
        end
      end
    end

    class Writer
      def initialize(io)
        @io = io
      end

      def write(**json)
        json = JSON.generate(json.merge(jsonrpc: "2.0"))
        @io << "Content-Length: #{ json.bytesize }\r\n\r\n" << json
        @io.flush
      end

      module ErrorCodes
        ParseError = -32700
        InvalidRequest = -32600
        MethodNotFound = -32601
        InvalidParams = -32602
        InternalError = -32603
      end
    end

    module Helpers
      def pos(line, character)
        { line: line, character: character }
      end

      def range(s, e)
        { start: s, end: e }
      end
    end

    class Server
      class Exit < StandardError; end

      include Helpers

      def initialize(config, reader, writer)
        @typeprof_config = config
        @reader = reader
        @writer = writer
        @tx_mutex = Mutex.new
        @request_id = 0
        @running_requests_from_client = {}
        @running_requests_from_server = {}
        @open_texts = {}
        @sigs = {} # tmp
        @signature_enabled = true
      end

      attr_reader :typeprof_config, :open_texts, :sigs, :running_requests_from_client
      attr_accessor :root_uri, :signature_enabled

      def run
        @reader.read do |json|
          if json[:method]
            # request or notification
            msg = Message.find(json[:method]).new(self, json)
            @running_requests_from_client[json[:id]] = msg if json[:id]
            msg.run
          else
            callback = @running_requests_from_server.delete(json[:id])
            callback&.call(json[:params])
          end
        end
      rescue Exit
      end

      def send_response(**msg)
        @running_requests_from_client.delete(msg[:id])
        exclusive_write(**msg)
      end

      def send_notification(method, params = nil)
        exclusive_write(method: method, params: params)
      end

      def send_request(method, **params, &blk)
        id = @request_id += 1
        @running_requests_from_server[id] = blk
        exclusive_write(id: id, method: method, params: params)
      end

      def exclusive_write(**json)
        @tx_mutex.synchronize do
          @writer.write(**json)
        end
      end
    end
  end
end
