# frozen_string_literal: true
##
# Parse a non-source file. We basically take the whole thing as one big
# comment.

class RDoc::Parser::Simple < RDoc::Parser

  include RDoc::Parser::Text

  parse_files_matching(//)

  attr_reader :content # :nodoc:

  ##
  # Prepare to parse a plain file

  def initialize(top_level, file_name, content, options, stats)
    super

    preprocess = RDoc::Markup::PreProcess.new @file_name, @options.rdoc_include

    @content = preprocess.handle @content, @top_level
  end

  ##
  # Extract the file contents and attach them to the TopLevel as a comment

  def scan
    comment = remove_coding_comment @content
    comment = remove_private_comment comment

    comment = RDoc::Comment.new comment, @top_level

    @top_level.comment = comment
    @top_level
  end

  ##
  # Removes the encoding magic comment from +text+

  def remove_coding_comment text
    text.sub(/\A# .*coding[=:].*$/, '')
  end

  ##
  # Removes private comments.
  #
  # Unlike RDoc::Comment#remove_private this implementation only looks for two
  # dashes at the beginning of the line.  Three or more dashes are considered
  # to be a rule and ignored.

  def remove_private_comment comment
    # Workaround for gsub encoding for Ruby 1.9.2 and earlier
    empty = ''
    empty = RDoc::Encoding.change_encoding empty, comment.encoding

    comment = comment.gsub(%r%^--\n.*?^\+\+\n?%m, empty)
    comment.sub(%r%^--\n.*%m, empty)
  end

end
