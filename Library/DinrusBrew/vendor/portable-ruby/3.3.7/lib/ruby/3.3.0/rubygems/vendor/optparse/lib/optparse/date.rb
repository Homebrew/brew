# frozen_string_literal: false
require_relative '../optparse'
require 'date'

Gem::OptionParser.accept(DateTime) do |s,|
  begin
    DateTime.parse(s) if s
  rescue ArgumentError
    raise Gem::OptionParser::InvalidArgument, s
  end
end
Gem::OptionParser.accept(Date) do |s,|
  begin
    Date.parse(s) if s
  rescue ArgumentError
    raise Gem::OptionParser::InvalidArgument, s
  end
end
