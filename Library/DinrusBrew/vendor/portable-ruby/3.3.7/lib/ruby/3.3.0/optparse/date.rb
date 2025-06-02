# frozen_string_literal: false
require_relative '../optparse'
require 'date'

OptionParser.accept(DateTime) do |s,|
  begin
    DateTime.parse(s) if s
  rescue ArgumentError
    raise OptionParser::InvalidArgument, s
  end
end
OptionParser.accept(Date) do |s,|
  begin
    Date.parse(s) if s
  rescue ArgumentError
    raise OptionParser::InvalidArgument, s
  end
end
