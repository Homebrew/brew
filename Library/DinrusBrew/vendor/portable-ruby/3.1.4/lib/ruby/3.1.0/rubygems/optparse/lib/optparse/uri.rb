# frozen_string_literal: false
# -*- ruby -*-

require_relative '../optparse'
require 'uri'

Gem::OptionParser.accept(URI) {|s,| URI.parse(s) if s}
