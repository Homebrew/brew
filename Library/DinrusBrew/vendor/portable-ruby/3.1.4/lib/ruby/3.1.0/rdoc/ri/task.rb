# frozen_string_literal: true
begin
  gem 'rdoc'
rescue Gem::LoadError
end unless defined?(RDoc)

require_relative '../task'

##
# RDoc::RI::Task creates ri data in <code>./.rdoc</code> for your project.
#
# It contains the following tasks:
#
# [ri]
#   Build ri data
#
# [clobber_ri]
#   Delete ri data files.  This target is automatically added to the main
#   clobber target.
#
# [reri]
#   Rebuild the ri data from scratch even if they are not out of date.
#
# Simple example:
#
#   require 'rdoc/ri/task'
#
#   RDoc::RI::Task.new do |ri|
#     ri.main = 'README.rdoc'
#     ri.rdoc_files.include 'README.rdoc', 'lib/**/*.rb'
#   end
#
# For further configuration details see RDoc::Task.

class RDoc::RI::Task < RDoc::Task

  DEFAULT_NAMES = { # :nodoc:
    :clobber_rdoc => :clobber_ri,
    :rdoc         => :ri,
    :rerdoc       => :reri,
  }

  ##
  # Create an ri task with the given name. See RDoc::Task for documentation on
  # setting names.

  def initialize name = DEFAULT_NAMES # :yield: self
    super
  end

  def clobber_task_description # :nodoc:
    "Remove RI data files"
  end

  ##
  # Sets default task values

  def defaults
    super

    @rdoc_dir = '.rdoc'
  end

  def rdoc_task_description # :nodoc:
    'Build RI data files'
  end

  def rerdoc_task_description # :nodoc:
    'Rebuild RI data files'
  end
end
