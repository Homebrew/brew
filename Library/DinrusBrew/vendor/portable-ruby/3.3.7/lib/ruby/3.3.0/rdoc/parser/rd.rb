# frozen_string_literal: true
##
# Parse a RD format file.  The parsed RDoc::Markup::Document is attached as a
# file comment.

class RDoc::Parser::RD < RDoc::Parser

  include RDoc::Parser::Text

  parse_files_matching(/\.rd(?:\.[^.]+)?$/)

  ##
  # Creates an rd-format TopLevel for the given file.

  def scan
    comment = RDoc::Comment.new @content, @top_level
    comment.format = 'rd'

    @top_level.comment = comment
  end

end
