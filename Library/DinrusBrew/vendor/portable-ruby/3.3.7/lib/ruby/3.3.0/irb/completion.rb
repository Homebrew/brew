# frozen_string_literal: true
#
#   irb/completion.rb -
#   	by Keiju ISHITSUKA(keiju@ishitsuka.com)
#       From Original Idea of shugo@ruby-lang.org
#

require_relative 'ruby-lex'

module IRB
  class BaseCompletor # :nodoc:

    # Set of reserved words used by Ruby, you should not use these for
    # constants or variables
    ReservedWords = %w[
      __ENCODING__ __LINE__ __FILE__
      BEGIN END
      alias and
      begin break
      case class
      def defined? do
      else elsif end ensure
      false for
      if in
      module
      next nil not
      or
      redo rescue retry return
      self super
      then true
      undef unless until
      when while
      yield
    ]

    def completion_candidates(preposing, target, postposing, bind:)
      raise NotImplementedError
    end

    def doc_namespace(preposing, matched, postposing, bind:)
      raise NotImplementedError
    end

    GEM_PATHS =
      if defined?(Gem::Specification)
        Gem::Specification.latest_specs(true).map { |s|
          s.require_paths.map { |p|
            if File.absolute_path?(p)
              p
            else
              File.join(s.full_gem_path, p)
            end
          }
        }.flatten
      else
        []
      end.freeze

    def retrieve_gem_and_system_load_path
      candidates = (GEM_PATHS | $LOAD_PATH)
      candidates.map do |p|
        if p.respond_to?(:to_path)
          p.to_path
        else
          String(p) rescue nil
        end
      end.compact.sort
    end

    def retrieve_files_to_require_from_load_path
      @files_from_load_path ||=
        (
          shortest = []
          rest = retrieve_gem_and_system_load_path.each_with_object([]) { |path, result|
            begin
              names = Dir.glob("**/*.{rb,#{RbConfig::CONFIG['DLEXT']}}", base: path)
            rescue Errno::ENOENT
              nil
            end
            next if names.empty?
            names.map! { |n| n.sub(/\.(rb|#{RbConfig::CONFIG['DLEXT']})\z/, '') }.sort!
            shortest << names.shift
            result.concat(names)
          }
          shortest.sort! | rest
        )
    end

    def command_completions(preposing, target)
      if preposing.empty? && !target.empty?
        IRB::Command.command_names.select { _1.start_with?(target) }
      else
        []
      end
    end

    def retrieve_files_to_require_relative_from_current_dir
      @files_from_current_dir ||= Dir.glob("**/*.{rb,#{RbConfig::CONFIG['DLEXT']}}", base: '.').map { |path|
        path.sub(/\.(rb|#{RbConfig::CONFIG['DLEXT']})\z/, '')
      }
    end
  end

  class TypeCompletor < BaseCompletor # :nodoc:
    def initialize(context)
      @context = context
    end

    def inspect
      ReplTypeCompletor.info
    end

    def completion_candidates(preposing, target, _postposing, bind:)
      commands = command_completions(preposing, target)
      result = ReplTypeCompletor.analyze(preposing + target, binding: bind, filename: @context.irb_path)
      return commands unless result

      commands | result.completion_candidates.map { target + _1 }
    end

    def doc_namespace(preposing, matched, _postposing, bind:)
      result = ReplTypeCompletor.analyze(preposing + matched, binding: bind, filename: @context.irb_path)
      result&.doc_namespace('')
    end
  end

  class RegexpCompletor < BaseCompletor # :nodoc:
    using Module.new {
      refine ::Binding do
        def eval_methods
          ::Kernel.instance_method(:methods).bind(eval("self")).call
        end

        def eval_private_methods
          ::Kernel.instance_method(:private_methods).bind(eval("self")).call
        end

        def eval_instance_variables
          ::Kernel.instance_method(:instance_variables).bind(eval("self")).call
        end

        def eval_global_variables
          ::Kernel.instance_method(:global_variables).bind(eval("self")).call
        end

        def eval_class_constants
          ::Module.instance_method(:constants).bind(eval("self.class")).call
        end
      end
    }

    def inspect
      'RegexpCompletor'
    end

    def complete_require_path(target, preposing, postposing)
      if target =~ /\A(['"])([^'"]+)\Z/
        quote = $1
        actual_target = $2
      else
        return nil # It's not String literal
      end
      tokens = RubyLex.ripper_lex_without_warning(preposing.gsub(/\s*\z/, ''))
      tok = nil
      tokens.reverse_each do |t|
        unless [:on_lparen, :on_sp, :on_ignored_sp, :on_nl, :on_ignored_nl, :on_comment].include?(t.event)
          tok = t
          break
        end
      end
      return unless tok&.event == :on_ident && tok.state == Ripper::EXPR_CMDARG

      case tok.tok
      when 'require'
        retrieve_files_to_require_from_load_path.select { |path|
          path.start_with?(actual_target)
        }.map { |path|
          quote + path
        }
      when 'require_relative'
        retrieve_files_to_require_relative_from_current_dir.select { |path|
          path.start_with?(actual_target)
        }.map { |path|
          quote + path
        }
      end
    end

    def completion_candidates(preposing, target, postposing, bind:)
      if preposing && postposing
        result = complete_require_path(target, preposing, postposing)
        return result if result
      end
      commands = command_completions(preposing || '', target)
      commands | retrieve_completion_data(target, bind: bind, doc_namespace: false).compact.map{ |i| i.encode(Encoding.default_external) }
    end

    def doc_namespace(_preposing, matched, _postposing, bind:)
      retrieve_completion_data(matched, bind: bind, doc_namespace: true)
    end

    def retrieve_completion_data(input, bind:, doc_namespace:)
      case input
      # this regexp only matches the closing character because of irb's Reline.completer_quote_characters setting
      # details are described in: https://github.com/ruby/irb/pull/523
      when /^(.*["'`])\.([^.]*)$/
        # String
        receiver = $1
        message = $2

        if doc_namespace
          "String.#{message}"
        else
          candidates = String.instance_methods.collect{|m| m.to_s}
          select_message(receiver, message, candidates)
        end

      # this regexp only matches the closing character because of irb's Reline.completer_quote_characters setting
      # details are described in: https://github.com/ruby/irb/pull/523
      when /^(.*\/)\.([^.]*)$/
        # Regexp
        receiver = $1
        message = $2

        if doc_namespace
          "Regexp.#{message}"
        else
          candidates = Regexp.instance_methods.collect{|m| m.to_s}
          select_message(receiver, message, candidates)
        end

      when /^([^\]]*\])\.([^.]*)$/
        # Array
        receiver = $1
        message = $2

        if doc_namespace
          "Array.#{message}"
        else
          candidates = Array.instance_methods.collect{|m| m.to_s}
          select_message(receiver, message, candidates)
        end

      when /^([^\}]*\})\.([^.]*)$/
        # Hash or Proc
        receiver = $1
        message = $2

        if doc_namespace
          ["Hash.#{message}", "Proc.#{message}"]
        else
          hash_candidates = Hash.instance_methods.collect{|m| m.to_s}
          proc_candidates = Proc.instance_methods.collect{|m| m.to_s}
          select_message(receiver, message, hash_candidates | proc_candidates)
        end

      when /^(:[^:.]+)$/
        # Symbol
        if doc_namespace
          nil
        else
          sym = $1
          candidates = Symbol.all_symbols.collect do |s|
            s.inspect
          rescue EncodingError
            # ignore
          end
          candidates.grep(/^#{Regexp.quote(sym)}/)
        end
      when /^::([A-Z][^:\.\(\)]*)$/
        # Absolute Constant or class methods
        receiver = $1

        candidates = Object.constants.collect{|m| m.to_s}

        if doc_namespace
          candidates.find { |i| i == receiver }
        else
          candidates.grep(/^#{Regexp.quote(receiver)}/).collect{|e| "::" + e}
        end

      when /^([A-Z].*)::([^:.]*)$/
        # Constant or class methods
        receiver = $1
        message = $2

        if doc_namespace
          "#{receiver}::#{message}"
        else
          begin
            candidates = eval("#{receiver}.constants.collect{|m| m.to_s}", bind)
            candidates |= eval("#{receiver}.methods.collect{|m| m.to_s}", bind)
          rescue Exception
            candidates = []
          end

          select_message(receiver, message, candidates.sort, "::")
        end

      when /^(:[^:.]+)(\.|::)([^.]*)$/
        # Symbol
        receiver = $1
        sep = $2
        message = $3

        if doc_namespace
          "Symbol.#{message}"
        else
          candidates = Symbol.instance_methods.collect{|m| m.to_s}
          select_message(receiver, message, candidates, sep)
        end

      when /^(?<num>-?(?:0[dbo])?[0-9_]+(?:\.[0-9_]+)?(?:(?:[eE][+-]?[0-9]+)?i?|r)?)(?<sep>\.|::)(?<mes>[^.]*)$/
        # Numeric
        receiver = $~[:num]
        sep = $~[:sep]
        message = $~[:mes]

        begin
          instance = eval(receiver, bind)

          if doc_namespace
            "#{instance.class.name}.#{message}"
          else
            candidates = instance.methods.collect{|m| m.to_s}
            select_message(receiver, message, candidates, sep)
          end
        rescue Exception
          if doc_namespace
            nil
          else
            []
          end
        end

      when /^(-?0x[0-9a-fA-F_]+)(\.|::)([^.]*)$/
        # Numeric(0xFFFF)
        receiver = $1
        sep = $2
        message = $3

        begin
          instance = eval(receiver, bind)
          if doc_namespace
            "#{instance.class.name}.#{message}"
          else
            candidates = instance.methods.collect{|m| m.to_s}
            select_message(receiver, message, candidates, sep)
          end
        rescue Exception
          if doc_namespace
            nil
          else
            []
          end
        end

      when /^(\$[^.]*)$/
        # global var
        gvar = $1
        all_gvars = global_variables.collect{|m| m.to_s}

        if doc_namespace
          all_gvars.find{ |i| i == gvar }
        else
          all_gvars.grep(Regexp.new(Regexp.quote(gvar)))
        end

      when /^([^.:"].*)(\.|::)([^.]*)$/
        # variable.func or func.func
        receiver = $1
        sep = $2
        message = $3

        gv = bind.eval_global_variables.collect{|m| m.to_s}.push("true", "false", "nil")
        lv = bind.local_variables.collect{|m| m.to_s}
        iv = bind.eval_instance_variables.collect{|m| m.to_s}
        cv = bind.eval_class_constants.collect{|m| m.to_s}

        if (gv | lv | iv | cv).include?(receiver) or /^[A-Z]/ =~ receiver && /\./ !~ receiver
          # foo.func and foo is var. OR
          # foo::func and foo is var. OR
          # foo::Const and foo is var. OR
          # Foo::Bar.func
          begin
            candidates = []
            rec = eval(receiver, bind)
            if sep == "::" and rec.kind_of?(Module)
              candidates = rec.constants.collect{|m| m.to_s}
            end
            candidates |= rec.methods.collect{|m| m.to_s}
          rescue Exception
            candidates = []
          end
        else
          # func1.func2
          candidates = []
        end

        if doc_namespace
          rec_class = rec.is_a?(Module) ? rec : rec.class
          "#{rec_class.name}#{sep}#{candidates.find{ |i| i == message }}" rescue nil
        else
          select_message(receiver, message, candidates, sep)
        end

      when /^\.([^.]*)$/
        # unknown(maybe String)

        receiver = ""
        message = $1

        candidates = String.instance_methods(true).collect{|m| m.to_s}

        if doc_namespace
          "String.#{candidates.find{ |i| i == message }}"
        else
          select_message(receiver, message, candidates.sort)
        end
      when /^\s*$/
        # empty input
        if doc_namespace
          nil
        else
          []
        end
      else
        if doc_namespace
          vars = (bind.local_variables | bind.eval_instance_variables).collect{|m| m.to_s}
          perfect_match_var = vars.find{|m| m.to_s == input}
          if perfect_match_var
            eval("#{perfect_match_var}.class.name", bind) rescue nil
          else
            candidates = (bind.eval_methods | bind.eval_private_methods | bind.local_variables | bind.eval_instance_variables | bind.eval_class_constants).collect{|m| m.to_s}
            candidates |= ReservedWords
            candidates.find{ |i| i == input }
          end
        else
          candidates = (bind.eval_methods | bind.eval_private_methods | bind.local_variables | bind.eval_instance_variables | bind.eval_class_constants).collect{|m| m.to_s}
          candidates |= ReservedWords
          candidates.grep(/^#{Regexp.quote(input)}/).sort
        end
      end
    end

    # Set of available operators in Ruby
    Operators = %w[% & * ** + - / < << <= <=> == === =~ > >= >> [] []= ^ ! != !~]

    def select_message(receiver, message, candidates, sep = ".")
      candidates.grep(/^#{Regexp.quote(message)}/).collect do |e|
        case e
        when /^[a-zA-Z_]/
          receiver + sep + e
        when /^[0-9]/
        when *Operators
          #receiver + " " + e
        end
      end
    end
  end

  module InputCompletor
    class << self
      private def regexp_completor
        @regexp_completor ||= RegexpCompletor.new
      end

      def retrieve_completion_data(input, bind: IRB.conf[:MAIN_CONTEXT].workspace.binding, doc_namespace: false)
        regexp_completor.retrieve_completion_data(input, bind: bind, doc_namespace: doc_namespace)
      end
    end
    CompletionProc = ->(target, preposing = nil, postposing = nil) {
      regexp_completor.completion_candidates(preposing, target, postposing, bind: IRB.conf[:MAIN_CONTEXT].workspace.binding)
    }
  end
  deprecate_constant :InputCompletor
end
