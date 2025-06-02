# frozen_string_literal: true
##
# Parse a Markdown format file.  The parsed RDoc::Markup::Document is attached
# as a file comment.

class RDoc::Parser::Markdown < RDoc::Parser

  include RDoc::Parser::Text

  parse_files_matching(/\.(md|markdown)(?:\.[^.]+)?$/)

  ##
  # Creates an Markdown-format TopLevel for the given file.

  def scan
    comment = RDoc::Comment.new @content, @top_level
    comment.format = 'markdown'

    @top_level.comment = comment
  end

end


