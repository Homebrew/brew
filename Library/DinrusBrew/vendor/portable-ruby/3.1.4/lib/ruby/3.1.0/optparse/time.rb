# frozen_string_literal: false
require 'optparse'
require 'time'

OptionParser.accept(Time) do |s,|
  begin
    (Time.httpdate(s) rescue Time.parse(s)) if s
  rescue
    raise OptionParser::InvalidArgument, s
  end
end
