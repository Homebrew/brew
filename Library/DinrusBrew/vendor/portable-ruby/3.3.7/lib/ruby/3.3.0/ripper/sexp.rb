# frozen_string_literal: true
#
# $Id$
#
# Copyright (c) 2004,2005 Minero Aoki
#
# This program is free software.
# You can distribute and/or modify this program under the Ruby License.
# For details of Ruby License, see ruby/COPYING.
#

require 'ripper/core'

class Ripper

  # [EXPERIMENTAL]
  # Parses +src+ and create S-exp tree.
  # Returns more readable tree rather than Ripper.sexp_raw.
  # This method is mainly for developer use.
  # The +filename+ argument is mostly ignored.
  # By default, this method does not handle syntax errors in +src+,
  # returning +nil+ in such cases. Use the +raise_errors+ keyword
  # to raise a SyntaxError for an error in +src+.
  #
  #   require 'ripper'
  #   require 'pp'
  #
  #   pp Ripper.sexp("def m(a) nil end")
  #     #=> [:program,
  #          [[:def,
  #           [:@ident, "m", [1, 4]],
  #           [:paren, [:params, [[:@ident, "a", [1, 6]]], nil, nil, nil, nil, nil, nil]],
  #           [:bodystmt, [[:var_ref, [:@kw, "nil", [1, 9]]]], nil, nil, nil]]]]
  #
  def Ripper.sexp(src, filename = '-', lineno = 1, raise_errors: false)
    builder = SexpBuilderPP.new(src, filename, lineno)
    sexp = builder.parse
    if builder.error?
      if raise_errors
        raise SyntaxError, builder.error
      end
    else
      sexp
    end
  end

  # [EXPERIMENTAL]
  # Parses +src+ and create S-exp tree.
  # This method is mainly for developer use.
  # The +filename+ argument is mostly ignored.
  # By default, this method does not handle syntax errors in +src+,
  # returning +nil+ in such cases. Use the +raise_errors+ keyword
  # to raise a SyntaxError for an error in +src+.
  #
  #   require 'ripper'
  #   require 'pp'
  #
  #   pp Ripper.sexp_raw("def m(a) nil end")
  #     #=> [:program,
  #          [:stmts_add,
  #           [:stmts_new],
  #           [:def,
  #            [:@ident, "m", [1, 4]],
  #            [:paren, [:params, [[:@ident, "a", [1, 6]]], nil, nil, nil]],
  #            [:bodystmt,
  #             [:stmts_add, [:stmts_new], [:var_ref, [:@kw, "nil", [1, 9]]]],
  #             nil,
  #             nil,
  #             nil]]]]
  #
  def Ripper.sexp_raw(src, filename = '-', lineno = 1, raise_errors: false)
    builder = SexpBuilder.new(src, filename, lineno)
    sexp = builder.parse
    if builder.error?
      if raise_errors
        raise SyntaxError, builder.error
      end
    else
      sexp
    end
  end

  class SexpBuilder < ::Ripper   #:nodoc:
    attr_reader :error

    private

    def dedent_element(e, width)
      if (n = dedent_string(e[1], width)) > 0
        e[2][1] += n
      end
      e
    end

    def on_heredoc_dedent(val, width)
      sub = proc do |cont|
        cont.map! do |e|
          if Array === e
            case e[0]
            when :@tstring_content
              e = dedent_element(e, width)
            when /_add\z/
              e[1] = sub[e[1]]
            end
          elsif String === e
            dedent_string(e, width)
          end
          e
        end
      end
      sub[val]
      val
    end

    events = private_instance_methods(false).grep(/\Aon_/) {$'.to_sym}
    (PARSER_EVENTS - events).each do |event|
      module_eval(<<-End, __FILE__, __LINE__ + 1)
        def on_#{event}(*args)
          args.unshift :#{event}
          args
        end
      End
    end

    SCANNER_EVENTS.each do |event|
      module_eval(<<-End, __FILE__, __LINE__ + 1)
        def on_#{event}(tok)
          [:@#{event}, tok, [lineno(), column()]]
        end
      End
    end

    def on_error(mesg)
      @error = mesg
    end
    remove_method :on_parse_error
    alias on_parse_error on_error
    alias compile_error on_error
  end

  class SexpBuilderPP < SexpBuilder #:nodoc:
    private

    def on_heredoc_dedent(val, width)
      val.map! do |e|
        next e if Symbol === e and /_content\z/ =~ e
        if Array === e and e[0] == :@tstring_content
          e = dedent_element(e, width)
        elsif String === e
          dedent_string(e, width)
        end
        e
      end
      val
    end

    def _dispatch_event_new
      []
    end

    def _dispatch_event_push(list, item)
      list.push item
      list
    end

    def on_mlhs_paren(list)
      [:mlhs, *list]
    end

    def on_mlhs_add_star(list, star)
      list.push([:rest_param, star])
    end

    def on_mlhs_add_post(list, post)
      list.concat(post)
    end

    PARSER_EVENT_TABLE.each do |event, arity|
      if /_new\z/ =~ event and arity == 0
        alias_method "on_#{event}", :_dispatch_event_new
      elsif /_add\z/ =~ event
        alias_method "on_#{event}", :_dispatch_event_push
      end
    end
  end

end
