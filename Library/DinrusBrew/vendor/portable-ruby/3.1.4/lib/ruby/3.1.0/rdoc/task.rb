# frozen_string_literal: true
#--
# Copyright (c) 2003, 2004 Jim Weirich, 2009 Eric Hodel
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#++

begin
  gem 'rdoc'
rescue Gem::LoadError
end unless defined?(RDoc)

begin
  gem 'rake'
rescue Gem::LoadError
end unless defined?(Rake)

require 'rdoc'
require 'rake'
require 'rake/tasklib'

##
# RDoc::Task creates the following rake tasks to generate and clean up RDoc
# output:
#
# [rdoc]
#   Main task for this RDoc task.
#
# [clobber_rdoc]
#   Delete all the rdoc files.  This target is automatically added to the main
#   clobber target.
#
# [rerdoc]
#   Rebuild the rdoc files from scratch, even if they are not out of date.
#
# Simple Example:
#
#   require 'rdoc/task'
#
#   RDoc::Task.new do |rdoc|
#     rdoc.main = "README.rdoc"
#     rdoc.rdoc_files.include("README.rdoc", "lib/**/*.rb")
#   end
#
# The +rdoc+ object passed to the block is an RDoc::Task object. See the
# attributes list for the RDoc::Task class for available customization options.
#
# == Specifying different task names
#
# You may wish to give the task a different name, such as if you are
# generating two sets of documentation.  For instance, if you want to have a
# development set of documentation including private methods:
#
#   require 'rdoc/task'
#
#   RDoc::Task.new :rdoc_dev do |rdoc|
#     rdoc.main = "README.doc"
#     rdoc.rdoc_files.include("README.rdoc", "lib/**/*.rb")
#     rdoc.options << "--all"
#   end
#
# The tasks would then be named :<em>rdoc_dev</em>,
# :clobber_<em>rdoc_dev</em>, and :re<em>rdoc_dev</em>.
#
# If you wish to have completely different task names, then pass a Hash as
# first argument. With the <tt>:rdoc</tt>, <tt>:clobber_rdoc</tt> and
# <tt>:rerdoc</tt> options, you can customize the task names to your liking.
#
# For example:
#
#   require 'rdoc/task'
#
#   RDoc::Task.new(:rdoc => "rdoc", :clobber_rdoc => "rdoc:clean",
#                  :rerdoc => "rdoc:force")
#
# This will create the tasks <tt>:rdoc</tt>, <tt>:rdoc:clean</tt> and
# <tt>:rdoc:force</tt>.

class RDoc::Task < Rake::TaskLib

  ##
  # Name of the main, top level task.  (default is :rdoc)

  attr_accessor :name

  ##
  # Comment markup format.  rdoc, rd and tomdoc are supported.  (default is
  # 'rdoc')

  attr_accessor :markup

  ##
  # Name of directory to receive the html output files. (default is "html")

  attr_accessor :rdoc_dir

  ##
  # Title of RDoc documentation. (defaults to rdoc's default)

  attr_accessor :title

  ##
  # Name of file to be used as the main, top level file of the RDoc. (default
  # is none)

  attr_accessor :main

  ##
  # Name of template to be used by rdoc. (defaults to rdoc's default)

  attr_accessor :template

  ##
  # Name of format generator (<tt>--format</tt>) used by rdoc. (defaults to
  # rdoc's default)

  attr_accessor :generator

  ##
  # List of files to be included in the rdoc generation. (default is [])

  attr_accessor :rdoc_files

  ##
  # Additional list of options to be passed rdoc.  (default is [])

  attr_accessor :options

  ##
  # Whether to run the rdoc process as an external shell (default is false)

  attr_accessor :external

  ##
  # Create an RDoc task with the given name. See the RDoc::Task class overview
  # for documentation.

  def initialize name = :rdoc # :yield: self
    defaults

    check_names name

    @name = name

    yield self if block_given?

    define
  end

  ##
  # Ensures that +names+ only includes names for the :rdoc, :clobber_rdoc and
  # :rerdoc.  If other names are given an ArgumentError is raised.

  def check_names names
    return unless Hash === names

    invalid_options =
      names.keys.map { |k| k.to_sym } - [:rdoc, :clobber_rdoc, :rerdoc]

    unless invalid_options.empty? then
      raise ArgumentError, "invalid options: #{invalid_options.join ', '}"
    end
  end

  ##
  # Task description for the clobber rdoc task or its renamed equivalent

  def clobber_task_description
    "Remove RDoc HTML files"
  end

  ##
  # Sets default task values

  def defaults
    @name = :rdoc
    @rdoc_files = Rake::FileList.new
    @rdoc_dir = 'html'
    @main = nil
    @title = nil
    @template = nil
    @generator = nil
    @options = []
  end

  ##
  # All source is inline now.  This method is deprecated

  def inline_source # :nodoc:
    warn "RDoc::Task#inline_source is deprecated"
    true
  end

  ##
  # All source is inline now.  This method is deprecated

  def inline_source=(value) # :nodoc:
    warn "RDoc::Task#inline_source is deprecated"
  end

  ##
  # Create the tasks defined by this task lib.

  def define
    desc rdoc_task_description
    task rdoc_task_name

    desc rerdoc_task_description
    task rerdoc_task_name => [clobber_task_name, rdoc_task_name]

    desc clobber_task_description
    task clobber_task_name do
      rm_r @rdoc_dir rescue nil
    end

    task :clobber => [clobber_task_name]

    directory @rdoc_dir

    rdoc_target_deps = [
      @rdoc_files,
      Rake.application.rakefile
    ].flatten.compact

    task rdoc_task_name => [rdoc_target]
    file rdoc_target => rdoc_target_deps do
      @before_running_rdoc.call if @before_running_rdoc
      args = option_list + @rdoc_files

      $stderr.puts "rdoc #{args.join ' '}" if Rake.application.options.trace
      RDoc::RDoc.new.document args
    end

    self
  end

  ##
  # List of options that will be supplied to RDoc

  def option_list
    result = @options.dup
    result << "-o"       << @rdoc_dir
    result << "--main"   << main      if main
    result << "--markup" << markup    if markup
    result << "--title"  << title     if title
    result << "-T"       << template  if template
    result << '-f'       << generator if generator
    result
  end

  ##
  # The block passed to this method will be called just before running the
  # RDoc generator. It is allowed to modify RDoc::Task attributes inside the
  # block.

  def before_running_rdoc(&block)
    @before_running_rdoc = block
  end

  ##
  # Task description for the rdoc task or its renamed equivalent

  def rdoc_task_description
    'Build RDoc HTML files'
  end

  ##
  # Task description for the rerdoc task or its renamed description

  def rerdoc_task_description
    "Rebuild RDoc HTML files"
  end

  private

  def rdoc_target
    "#{rdoc_dir}/created.rid"
  end

  def rdoc_task_name
    case name
    when Hash then (name[:rdoc] || "rdoc").to_s
    else           name.to_s
    end
  end

  def clobber_task_name
    case name
    when Hash then (name[:clobber_rdoc] || "clobber_rdoc").to_s
    else           "clobber_#{name}"
    end
  end

  def rerdoc_task_name
    case name
    when Hash then (name[:rerdoc] || "rerdoc").to_s
    else           "re#{name}"
    end
  end

end

# :stopdoc:
module Rake

  ##
  # For backwards compatibility

  RDocTask = RDoc::Task

end
# :startdoc:
