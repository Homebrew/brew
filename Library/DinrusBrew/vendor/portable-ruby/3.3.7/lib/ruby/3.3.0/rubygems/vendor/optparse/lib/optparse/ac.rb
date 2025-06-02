# frozen_string_literal: false
require_relative '../optparse'

class Gem::OptionParser::AC < Gem::OptionParser
  private

  def _check_ac_args(name, block)
    unless /\A\w[-\w]*\z/ =~ name
      raise ArgumentError, name
    end
    unless block
      raise ArgumentError, "no block given", ParseError.filter_backtrace(caller)
    end
  end

  ARG_CONV = proc {|val| val.nil? ? true : val}

  def _ac_arg_enable(prefix, name, help_string, block)
    _check_ac_args(name, block)

    sdesc = []
    ldesc = ["--#{prefix}-#{name}"]
    desc = [help_string]
    q = name.downcase
    ac_block = proc {|val| block.call(ARG_CONV.call(val))}
    enable = Switch::PlacedArgument.new(nil, ARG_CONV, sdesc, ldesc, nil, desc, ac_block)
    disable = Switch::NoArgument.new(nil, proc {false}, sdesc, ldesc, nil, desc, ac_block)
    top.append(enable, [], ["enable-" + q], disable, ['disable-' + q])
    enable
  end

  public

  def ac_arg_enable(name, help_string, &block)
    _ac_arg_enable("enable", name, help_string, block)
  end

  def ac_arg_disable(name, help_string, &block)
    _ac_arg_enable("disable", name, help_string, block)
  end

  def ac_arg_with(name, help_string, &block)
    _check_ac_args(name, block)

    sdesc = []
    ldesc = ["--with-#{name}"]
    desc = [help_string]
    q = name.downcase
    with = Switch::PlacedArgument.new(*search(:atype, String), sdesc, ldesc, nil, desc, block)
    without = Switch::NoArgument.new(nil, proc {}, sdesc, ldesc, nil, desc, block)
    top.append(with, [], ["with-" + q], without, ['without-' + q])
    with
  end
end
