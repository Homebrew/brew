# frozen_string_literal: true
##
# A file included at generation time.  Objects of this class are created by
# RDoc::RD for an extension-less include.
#
# This implementation in incomplete.

class RDoc::Markup::Include

  ##
  # The filename to be included, without extension

  attr_reader :file

  ##
  # Directories to search for #file

  attr_reader :include_path

  ##
  # Creates a new include that will import +file+ from +include_path+

  def initialize file, include_path
    @file = file
    @include_path = include_path
  end

  def == other # :nodoc:
    self.class === other and
      @file == other.file and @include_path == other.include_path
  end

  def pretty_print q # :nodoc:
    q.group 2, '[incl ', ']' do
      q.text file
      q.breakable
      q.text 'from '
      q.pp include_path
    end
  end

end

