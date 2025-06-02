# frozen_string_literal: false
# -*- ruby -*-

require 'shellwords'
require_relative '../optparse'

OptionParser.accept(Shellwords) {|s,| Shellwords.shellwords(s)}
