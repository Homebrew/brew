#--
#
#
#
# Copyright (c) 1999-2006 Minero Aoki
#
# This program is free software.
# You can distribute/modify this program under the same terms of ruby.
# see the file "COPYING".
#
#++

module Racc

  class SourceText
    def initialize(text, filename, lineno)
      @text = text
      @filename = filename
      @lineno = lineno
    end

    attr_reader :text
    attr_reader :filename
    attr_reader :lineno

    def to_s
      "#<SourceText #{location()}>"
    end

    def location
      "#{@filename}:#{@lineno}"
    end
  end

end
