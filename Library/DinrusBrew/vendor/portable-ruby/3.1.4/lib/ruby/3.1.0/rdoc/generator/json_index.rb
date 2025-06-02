# frozen_string_literal: true
require 'json'
begin
  require 'zlib'
rescue LoadError
end

##
# The JsonIndex generator is designed to complement an HTML generator and
# produces a JSON search index.  This generator is derived from sdoc by
# Vladimir Kolesnikov and contains verbatim code written by him.
#
# This generator is designed to be used with a regular HTML generator:
#
#   class RDoc::Generator::Darkfish
#     def initialize options
#       # ...
#       @base_dir = Pathname.pwd.expand_path
#
#       @json_index = RDoc::Generator::JsonIndex.new self, options
#     end
#
#     def generate
#       # ...
#       @json_index.generate
#     end
#   end
#
# == Index Format
#
# The index is output as a JSON file assigned to the global variable
# +search_data+.  The structure is:
#
#   var search_data = {
#     "index": {
#       "searchIndex":
#         ["a", "b", ...],
#       "longSearchIndex":
#         ["a", "a::b", ...],
#       "info": [
#         ["A", "A", "A.html", "", ""],
#         ["B", "A::B", "A::B.html", "", ""],
#         ...
#       ]
#     }
#   }
#
# The same item is described across the +searchIndex+, +longSearchIndex+ and
# +info+ fields.  The +searchIndex+ field contains the item's short name, the
# +longSearchIndex+ field contains the full_name (when appropriate) and the
# +info+ field contains the item's name, full_name, path, parameters and a
# snippet of the item's comment.
#
# == LICENSE
#
# Copyright (c) 2009 Vladimir Kolesnikov
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

class RDoc::Generator::JsonIndex

  include RDoc::Text

  ##
  # Where the search index lives in the generated output

  SEARCH_INDEX_FILE = File.join 'js', 'search_index.js'

  attr_reader :index # :nodoc:

  ##
  # Creates a new generator.  +parent_generator+ is used to determine the
  # class_dir and file_dir of links in the output index.
  #
  # +options+ are the same options passed to the parent generator.

  def initialize parent_generator, options
    @parent_generator = parent_generator
    @store            = parent_generator.store
    @options          = options

    @template_dir = File.expand_path '../template/json_index', __FILE__
    @base_dir = @parent_generator.base_dir

    @classes = nil
    @files   = nil
    @index   = nil
  end

  ##
  # Builds the JSON index as a Hash.

  def build_index
    reset @store.all_files.sort, @store.all_classes_and_modules.sort

    index_classes
    index_methods
    index_pages

    { :index => @index }
  end

  ##
  # Output progress information if debugging is enabled

  def debug_msg *msg
    return unless $DEBUG_RDOC
    $stderr.puts(*msg)
  end

  ##
  # Writes the JSON index to disk

  def generate
    debug_msg "Generating JSON index"

    debug_msg "  writing search index to %s" % SEARCH_INDEX_FILE
    data = build_index

    return if @options.dry_run

    out_dir = @base_dir + @options.op_dir
    index_file = out_dir + SEARCH_INDEX_FILE

    FileUtils.mkdir_p index_file.dirname, :verbose => $DEBUG_RDOC

    index_file.open 'w', 0644 do |io|
      io.set_encoding Encoding::UTF_8
      io.write 'var search_data = '

      JSON.dump data, io, 0
    end
    unless ENV['SOURCE_DATE_EPOCH'].nil?
      index_file.utime index_file.atime, Time.at(ENV['SOURCE_DATE_EPOCH'].to_i).gmtime
    end

    Dir.chdir @template_dir do
      Dir['**/*.js'].each do |source|
        dest = File.join out_dir, source

        FileUtils.install source, dest, :mode => 0644, :preserve => true, :verbose => $DEBUG_RDOC
      end
    end
  end

  ##
  # Compress the search_index.js file using gzip

  def generate_gzipped
    return if @options.dry_run or not defined?(Zlib)

    debug_msg "Compressing generated JSON index"
    out_dir = @base_dir + @options.op_dir

    search_index_file = out_dir + SEARCH_INDEX_FILE
    outfile           = out_dir + "#{search_index_file}.gz"

    debug_msg "Reading the JSON index file from %s" % search_index_file
    search_index = search_index_file.read(mode: 'r:utf-8')

    debug_msg "Writing gzipped search index to %s" % outfile

    Zlib::GzipWriter.open(outfile) do |gz|
      gz.mtime = File.mtime(search_index_file)
      gz.orig_name = search_index_file.basename.to_s
      gz.write search_index
      gz.close
    end

    # GZip the rest of the js files
    Dir.chdir @template_dir do
      Dir['**/*.js'].each do |source|
        dest = out_dir + source
        outfile = out_dir + "#{dest}.gz"

        debug_msg "Reading the original js file from %s" % dest
        data = dest.read

        debug_msg "Writing gzipped file to %s" % outfile

        Zlib::GzipWriter.open(outfile) do |gz|
          gz.mtime = File.mtime(dest)
          gz.orig_name = dest.basename.to_s
          gz.write data
          gz.close
        end
      end
    end
  end

  ##
  # Adds classes and modules to the index

  def index_classes
    debug_msg "  generating class search index"

    documented = @classes.uniq.select do |klass|
      klass.document_self_or_methods
    end

    documented.each do |klass|
      debug_msg "    #{klass.full_name}"
      record = klass.search_record
      @index[:searchIndex]     << search_string(record.shift)
      @index[:longSearchIndex] << search_string(record.shift)
      @index[:info]            << record
    end
  end

  ##
  # Adds methods to the index

  def index_methods
    debug_msg "  generating method search index"

    list = @classes.uniq.map do |klass|
      klass.method_list
    end.flatten.sort_by do |method|
      [method.name, method.parent.full_name]
    end

    list.each do |method|
      debug_msg "    #{method.full_name}"
      record = method.search_record
      @index[:searchIndex]     << "#{search_string record.shift}()"
      @index[:longSearchIndex] << "#{search_string record.shift}()"
      @index[:info]            << record
    end
  end

  ##
  # Adds pages to the index

  def index_pages
    debug_msg "  generating pages search index"

    pages = @files.select do |file|
      file.text?
    end

    pages.each do |page|
      debug_msg "    #{page.page_name}"
      record = page.search_record
      @index[:searchIndex]     << search_string(record.shift)
      @index[:longSearchIndex] << ''
      record.shift
      @index[:info]            << record
    end
  end

  ##
  # The directory classes are written to

  def class_dir
    @parent_generator.class_dir
  end

  ##
  # The directory files are written to

  def file_dir
    @parent_generator.file_dir
  end

  def reset files, classes # :nodoc:
    @files   = files
    @classes = classes

    @index = {
      :searchIndex => [],
      :longSearchIndex => [],
      :info => []
    }
  end

  ##
  # Removes whitespace and downcases +string+

  def search_string string
    string.downcase.gsub(/\s/, '')
  end

end
