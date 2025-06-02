# frozen_string_literal: false
require_relative '../optparse'
require 'time'

Gem::OptionParser.accept(Time) do |s,|
  begin
    (Time.httpdate(s) rescue Time.parse(s)) if s
  rescue
    raise Gem::OptionParser::InvalidArgument, s
  end
end
