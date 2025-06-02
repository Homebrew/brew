# encoding: US-ASCII
# frozen_string_literal: true
# = csv.rb -- CSV Reading and Writing
#
# Created by James Edward Gray II on 2005-10-31.
#
# See CSV for documentation.
#
# == Description
#
# Welcome to the new and improved CSV.
#
# This version of the CSV library began its life as FasterCSV. FasterCSV was
# intended as a replacement to Ruby's then standard CSV library. It was
# designed to address concerns users of that library had and it had three
# primary goals:
#
# 1.  Be significantly faster than CSV while remaining a pure Ruby library.
# 2.  Use a smaller and easier to maintain code base. (FasterCSV eventually
#     grew larger, was also but considerably richer in features. The parsing
#     core remains quite small.)
# 3.  Improve on the CSV interface.
#
# Obviously, the last one is subjective. I did try to defer to the original
# interface whenever I didn't have a compelling reason to change it though, so
# hopefully this won't be too radically different.
#
# We must have met our goals because FasterCSV was renamed to CSV and replaced
# the original library as of Ruby 1.9. If you are migrating code from 1.8 or
# earlier, you may have to change your code to comply with the new interface.
#
# == What's the Different From the Old CSV?
#
# I'm sure I'll miss something, but I'll try to mention most of the major
# differences I am aware of, to help others quickly get up to speed:
#
# === \CSV Parsing
#
# * This parser is m17n aware. See CSV for full details.
# * This library has a stricter parser and will throw MalformedCSVErrors on
#   problematic data.
# * This library has a less liberal idea of a line ending than CSV. What you
#   set as the <tt>:row_sep</tt> is law. It can auto-detect your line endings
#   though.
# * The old library returned empty lines as <tt>[nil]</tt>. This library calls
#   them <tt>[]</tt>.
# * This library has a much faster parser.
#
# === Interface
#
# * CSV now uses keyword parameters to set options.
# * CSV no longer has generate_row() or parse_row().
# * The old CSV's Reader and Writer classes have been dropped.
# * CSV::open() is now more like Ruby's open().
# * CSV objects now support most standard IO methods.
# * CSV now has a new() method used to wrap objects like String and IO for
#   reading and writing.
# * CSV::generate() is different from the old method.
# * CSV no longer supports partial reads. It works line-by-line.
# * CSV no longer allows the instance methods to override the separators for
#   performance reasons. They must be set in the constructor.
#
# If you use this library and find yourself missing any functionality I have
# trimmed, please {let me know}[mailto:james@grayproductions.net].
#
# == Documentation
#
# See CSV for documentation.
#
# == What is CSV, really?
#
# CSV maintains a pretty strict definition of CSV taken directly from
# {the RFC}[https://www.ietf.org/rfc/rfc4180.txt]. I relax the rules in only one
# place and that is to make using this library easier. CSV will parse all valid
# CSV.
#
# What you don't want to do is to feed CSV invalid data. Because of the way the
# CSV format works, it's common for a parser to need to read until the end of
# the file to be sure a field is invalid. This consumes a lot of time and memory.
#
# Luckily, when working with invalid CSV, Ruby's built-in methods will almost
# always be superior in every way. For example, parsing non-quoted fields is as
# easy as:
#
#   data.split(",")
#
# == Questions and/or Comments
#
# Feel free to email {James Edward Gray II}[mailto:james@grayproductions.net]
# with any questions.

require "forwardable"
require "date"
require "stringio"

require_relative "csv/fields_converter"
require_relative "csv/input_record_separator"
require_relative "csv/parser"
require_relative "csv/row"
require_relative "csv/table"
require_relative "csv/writer"

# == \CSV
#
# === \CSV Data
#
# \CSV (comma-separated values) data is a text representation of a table:
# - A _row_ _separator_ delimits table rows.
#   A common row separator is the newline character <tt>"\n"</tt>.
# - A _column_ _separator_ delimits fields in a row.
#   A common column separator is the comma character <tt>","</tt>.
#
# This \CSV \String, with row separator <tt>"\n"</tt>
# and column separator <tt>","</tt>,
# has three rows and two columns:
#   "foo,0\nbar,1\nbaz,2\n"
#
# Despite the name \CSV, a \CSV representation can use different separators.
#
# For more about tables, see the Wikipedia article
# "{Table (information)}[https://en.wikipedia.org/wiki/Table_(information)]",
# especially its section
# "{Simple table}[https://en.wikipedia.org/wiki/Table_(information)#Simple_table]"
#
# == \Class \CSV
#
# Class \CSV provides methods for:
# - Parsing \CSV data from a \String object, a \File (via its file path), or an \IO object.
# - Generating \CSV data to a \String object.
#
# To make \CSV available:
#   require 'csv'
#
# All examples here assume that this has been done.
#
# == Keeping It Simple
#
# A \CSV object has dozens of instance methods that offer fine-grained control
# of parsing and generating \CSV data.
# For many needs, though, simpler approaches will do.
#
# This section summarizes the singleton methods in \CSV
# that allow you to parse and generate without explicitly
# creating \CSV objects.
# For details, follow the links.
#
# === Simple Parsing
#
# Parsing methods commonly return either of:
# - An \Array of Arrays of Strings:
#   - The outer \Array is the entire "table".
#   - Each inner \Array is a row.
#   - Each \String is a field.
# - A CSV::Table object.  For details, see
#   {\CSV with Headers}[#class-CSV-label-CSV+with+Headers].
#
# ==== Parsing a \String
#
# The input to be parsed can be a string:
#   string = "foo,0\nbar,1\nbaz,2\n"
#
# \Method CSV.parse returns the entire \CSV data:
#   CSV.parse(string) # => [["foo", "0"], ["bar", "1"], ["baz", "2"]]
#
# \Method CSV.parse_line returns only the first row:
#   CSV.parse_line(string) # => ["foo", "0"]
#
# \CSV extends class \String with instance method String#parse_csv,
# which also returns only the first row:
#   string.parse_csv # => ["foo", "0"]
#
# ==== Parsing Via a \File Path
#
# The input to be parsed can be in a file:
#   string = "foo,0\nbar,1\nbaz,2\n"
#   path = 't.csv'
#   File.write(path, string)
#
# \Method CSV.read returns the entire \CSV data:
#  CSV.read(path) # => [["foo", "0"], ["bar", "1"], ["baz", "2"]]
#
# \Method CSV.foreach iterates, passing each row to the given block:
#  CSV.foreach(path) do |row|
#    p row
#  end
# Output:
#   ["foo", "0"]
#   ["bar", "1"]
#   ["baz", "2"]
#
# \Method CSV.table returns the entire \CSV data as a CSV::Table object:
#   CSV.table(path) # => #<CSV::Table mode:col_or_row row_count:3>
#
# ==== Parsing from an Open \IO Stream
#
# The input to be parsed can be in an open \IO stream:
#
# \Method CSV.read returns the entire \CSV data:
#   File.open(path) do |file|
#     CSV.read(file)
#   end # => [["foo", "0"], ["bar", "1"], ["baz", "2"]]
#
# As does method CSV.parse:
#   File.open(path) do |file|
#     CSV.parse(file)
#   end # => [["foo", "0"], ["bar", "1"], ["baz", "2"]]
#
# \Method CSV.parse_line returns only the first row:
#   File.open(path) do |file|
#    CSV.parse_line(file)
#   end # => ["foo", "0"]
#
# \Method CSV.foreach iterates, passing each row to the given block:
#   File.open(path) do |file|
#     CSV.foreach(file) do |row|
#       p row
#     end
#   end
# Output:
#   ["foo", "0"]
#   ["bar", "1"]
#   ["baz", "2"]
#
# \Method CSV.table returns the entire \CSV data as a CSV::Table object:
#   File.open(path) do |file|
#     CSV.table(file)
#   end # => #<CSV::Table mode:col_or_row row_count:3>
#
# === Simple Generating
#
# \Method CSV.generate returns a \String;
# this example uses method CSV#<< to append the rows
# that are to be generated:
#   output_string = CSV.generate do |csv|
#     csv << ['foo', 0]
#     csv << ['bar', 1]
#     csv << ['baz', 2]
#   end
#   output_string # => "foo,0\nbar,1\nbaz,2\n"
#
# \Method CSV.generate_line returns a \String containing the single row
# constructed from an \Array:
#   CSV.generate_line(['foo', '0']) # => "foo,0\n"
#
# \CSV extends class \Array with instance method <tt>Array#to_csv</tt>,
# which forms an \Array into a \String:
#   ['foo', '0'].to_csv # => "foo,0\n"
#
# === "Filtering" \CSV
#
# \Method CSV.filter provides a Unix-style filter for \CSV data.
# The input data is processed to form the output data:
#   in_string = "foo,0\nbar,1\nbaz,2\n"
#   out_string = ''
#   CSV.filter(in_string, out_string) do |row|
#     row[0] = row[0].upcase
#     row[1] *= 4
#   end
#   out_string # => "FOO,0000\nBAR,1111\nBAZ,2222\n"
#
# == \CSV Objects
#
# There are three ways to create a \CSV object:
# - \Method CSV.new returns a new \CSV object.
# - \Method CSV.instance returns a new or cached \CSV object.
# - \Method \CSV() also returns a new or cached \CSV object.
#
# === Instance Methods
#
# \CSV has three groups of instance methods:
# - Its own internally defined instance methods.
# - Methods included by module Enumerable.
# - Methods delegated to class IO. See below.
#
# ==== Delegated Methods
#
# For convenience, a CSV object will delegate to many methods in class IO.
# (A few have wrapper "guard code" in \CSV.) You may call:
# * IO#binmode
# * #binmode?
# * IO#close
# * IO#close_read
# * IO#close_write
# * IO#closed?
# * #eof
# * #eof?
# * IO#external_encoding
# * IO#fcntl
# * IO#fileno
# * #flock
# * IO#flush
# * IO#fsync
# * IO#internal_encoding
# * #ioctl
# * IO#isatty
# * #path
# * IO#pid
# * IO#pos
# * IO#pos=
# * IO#reopen
# * #rewind
# * IO#seek
# * #stat
# * IO#string
# * IO#sync
# * IO#sync=
# * IO#tell
# * #to_i
# * #to_io
# * IO#truncate
# * IO#tty?
#
# === Options
#
# The default values for options are:
#   DEFAULT_OPTIONS = {
#     # For both parsing and generating.
#     col_sep:            ",",
#     row_sep:            :auto,
#     quote_char:         '"',
#     # For parsing.
#     field_size_limit:   nil,
#     converters:         nil,
#     unconverted_fields: nil,
#     headers:            false,
#     return_headers:     false,
#     header_converters:  nil,
#     skip_blanks:        false,
#     skip_lines:         nil,
#     liberal_parsing:    false,
#     nil_value:          nil,
#     empty_value:        "",
#     strip:              false,
#     # For generating.
#     write_headers:      nil,
#     quote_empty:        true,
#     force_quotes:       false,
#     write_converters:   nil,
#     write_nil_value:    nil,
#     write_empty_value:  "",
#   }
#
# ==== Options for Parsing
#
# Options for parsing, described in detail below, include:
# - +row_sep+: Specifies the row separator; used to delimit rows.
# - +col_sep+: Specifies the column separator; used to delimit fields.
# - +quote_char+: Specifies the quote character; used to quote fields.
# - +field_size_limit+: Specifies the maximum field size + 1 allowed.
#   Deprecated since 3.2.3. Use +max_field_size+ instead.
# - +max_field_size+: Specifies the maximum field size allowed.
# - +converters+: Specifies the field converters to be used.
# - +unconverted_fields+: Specifies whether unconverted fields are to be available.
# - +headers+: Specifies whether data contains headers,
#   or specifies the headers themselves.
# - +return_headers+: Specifies whether headers are to be returned.
# - +header_converters+: Specifies the header converters to be used.
# - +skip_blanks+: Specifies whether blanks lines are to be ignored.
# - +skip_lines+: Specifies how comments lines are to be recognized.
# - +strip+: Specifies whether leading and trailing whitespace are to be
#   stripped from fields. This must be compatible with +col_sep+; if it is not,
#   then an +ArgumentError+ exception will be raised.
# - +liberal_parsing+: Specifies whether \CSV should attempt to parse
#   non-compliant data.
# - +nil_value+: Specifies the object that is to be substituted for each null (no-text) field.
# - +empty_value+: Specifies the object that is to be substituted for each empty field.
#
# :include: ../doc/csv/options/common/row_sep.rdoc
#
# :include: ../doc/csv/options/common/col_sep.rdoc
#
# :include: ../doc/csv/options/common/quote_char.rdoc
#
# :include: ../doc/csv/options/parsing/field_size_limit.rdoc
#
# :include: ../doc/csv/options/parsing/converters.rdoc
#
# :include: ../doc/csv/options/parsing/unconverted_fields.rdoc
#
# :include: ../doc/csv/options/parsing/headers.rdoc
#
# :include: ../doc/csv/options/parsing/return_headers.rdoc
#
# :include: ../doc/csv/options/parsing/header_converters.rdoc
#
# :include: ../doc/csv/options/parsing/skip_blanks.rdoc
#
# :include: ../doc/csv/options/parsing/skip_lines.rdoc
#
# :include: ../doc/csv/options/parsing/strip.rdoc
#
# :include: ../doc/csv/options/parsing/liberal_parsing.rdoc
#
# :include: ../doc/csv/options/parsing/nil_value.rdoc
#
# :include: ../doc/csv/options/parsing/empty_value.rdoc
#
# ==== Options for Generating
#
# Options for generating, described in detail below, include:
# - +row_sep+: Specifies the row separator; used to delimit rows.
# - +col_sep+: Specifies the column separator; used to delimit fields.
# - +quote_char+: Specifies the quote character; used to quote fields.
# - +write_headers+: Specifies whether headers are to be written.
# - +force_quotes+: Specifies whether each output field is to be quoted.
# - +quote_empty+: Specifies whether each empty output field is to be quoted.
# - +write_converters+: Specifies the field converters to be used in writing.
# - +write_nil_value+: Specifies the object that is to be substituted for each +nil+-valued field.
# - +write_empty_value+: Specifies the object that is to be substituted for each empty field.
#
# :include: ../doc/csv/options/common/row_sep.rdoc
#
# :include: ../doc/csv/options/common/col_sep.rdoc
#
# :include: ../doc/csv/options/common/quote_char.rdoc
#
# :include: ../doc/csv/options/generating/write_headers.rdoc
#
# :include: ../doc/csv/options/generating/force_quotes.rdoc
#
# :include: ../doc/csv/options/generating/quote_empty.rdoc
#
# :include: ../doc/csv/options/generating/write_converters.rdoc
#
# :include: ../doc/csv/options/generating/write_nil_value.rdoc
#
# :include: ../doc/csv/options/generating/write_empty_value.rdoc
#
# === \CSV with Headers
#
# CSV allows to specify column names of CSV file, whether they are in data, or
# provided separately. If headers are specified, reading methods return an instance
# of CSV::Table, consisting of CSV::Row.
#
#   # Headers are part of data
#   data = CSV.parse(<<~ROWS, headers: true)
#     Name,Department,Salary
#     Bob,Engineering,1000
#     Jane,Sales,2000
#     John,Management,5000
#   ROWS
#
#   data.class      #=> CSV::Table
#   data.first      #=> #<CSV::Row "Name":"Bob" "Department":"Engineering" "Salary":"1000">
#   data.first.to_h #=> {"Name"=>"Bob", "Department"=>"Engineering", "Salary"=>"1000"}
#
#   # Headers provided by developer
#   data = CSV.parse('Bob,Engineering,1000', headers: %i[name department salary])
#   data.first      #=> #<CSV::Row name:"Bob" department:"Engineering" salary:"1000">
#
# === \Converters
#
# By default, each value (field or header) parsed by \CSV is formed into a \String.
# You can use a _field_ _converter_ or  _header_ _converter_
# to intercept and modify the parsed values:
# - See {Field Converters}[#class-CSV-label-Field+Converters].
# - See {Header Converters}[#class-CSV-label-Header+Converters].
#
# Also by default, each value to be written during generation is written 'as-is'.
# You can use a _write_ _converter_ to modify values before writing.
# - See {Write Converters}[#class-CSV-label-Write+Converters].
#
# ==== Specifying \Converters
#
# You can specify converters for parsing or generating in the +options+
# argument to various \CSV methods:
# - Option +converters+ for converting parsed field values.
# - Option +header_converters+ for converting parsed header values.
# - Option +write_converters+ for converting values to be written (generated).
#
# There are three forms for specifying converters:
# - A converter proc: executable code to be used for conversion.
# - A converter name: the name of a stored converter.
# - A converter list: an array of converter procs, converter names, and converter lists.
#
# ===== Converter Procs
#
# This converter proc, +strip_converter+, accepts a value +field+
# and returns <tt>field.strip</tt>:
#   strip_converter = proc {|field| field.strip }
# In this call to <tt>CSV.parse</tt>,
# the keyword argument <tt>converters: string_converter</tt>
# specifies that:
# - \Proc +string_converter+ is to be called for each parsed field.
# - The converter's return value is to replace the +field+ value.
# Example:
#   string = " foo , 0 \n bar , 1 \n baz , 2 \n"
#   array = CSV.parse(string, converters: strip_converter)
#   array # => [["foo", "0"], ["bar", "1"], ["baz", "2"]]
#
# A converter proc can receive a second argument, +field_info+,
# that contains details about the field.
# This modified +strip_converter+ displays its arguments:
#   strip_converter = proc do |field, field_info|
#     p [field, field_info]
#     field.strip
#   end
#   string = " foo , 0 \n bar , 1 \n baz , 2 \n"
#   array = CSV.parse(string, converters: strip_converter)
#   array # => [["foo", "0"], ["bar", "1"], ["baz", "2"]]
# Output:
#  [" foo ", #<struct CSV::FieldInfo index=0, line=1, header=nil>]
#  [" 0 ", #<struct CSV::FieldInfo index=1, line=1, header=nil>]
#  [" bar ", #<struct CSV::FieldInfo index=0, line=2, header=nil>]
#  [" 1 ", #<struct CSV::FieldInfo index=1, line=2, header=nil>]
#  [" baz ", #<struct CSV::FieldInfo index=0, line=3, header=nil>]
#  [" 2 ", #<struct CSV::FieldInfo index=1, line=3, header=nil>]
# Each CSV::FieldInfo object shows:
# - The 0-based field index.
# - The 1-based line index.
# - The field header, if any.
#
# ===== Stored \Converters
#
# A converter may be given a name and stored in a structure where
# the parsing methods can find it by name.
#
# The storage structure for field converters is the \Hash CSV::Converters.
# It has several built-in converter procs:
# - <tt>:integer</tt>: converts each \String-embedded integer into a true \Integer.
# - <tt>:float</tt>: converts each \String-embedded float into a true \Float.
# - <tt>:date</tt>: converts each \String-embedded date into a true \Date.
# - <tt>:date_time</tt>: converts each \String-embedded date-time into a true \DateTime
# .
# This example creates a converter proc, then stores it:
#   strip_converter = proc {|field| field.strip }
#   CSV::Converters[:strip] = strip_converter
# Then the parsing method call can refer to the converter
# by its name, <tt>:strip</tt>:
#   string = " foo , 0 \n bar , 1 \n baz , 2 \n"
#   array = CSV.parse(string, converters: :strip)
#   array # => [["foo", "0"], ["bar", "1"], ["baz", "2"]]
#
# The storage structure for header converters is the \Hash CSV::HeaderConverters,
# which works in the same way.
# It also has built-in converter procs:
# - <tt>:downcase</tt>: Downcases each header.
# - <tt>:symbol</tt>: Converts each header to a \Symbol.
#
# There is no such storage structure for write headers.
#
# In order for the parsing methods to access stored converters in non-main-Ractors, the
# storage structure must be made shareable first.
# Therefore, <tt>Ractor.make_shareable(CSV::Converters)</tt> and
# <tt>Ractor.make_shareable(CSV::HeaderConverters)</tt> must be called before the creation
# of Ractors that use the converters stored in these structures. (Since making the storage
# structures shareable involves freezing them, any custom converters that are to be used
# must be added first.)
#
# ===== Converter Lists
#
# A _converter_ _list_ is an \Array that may include any assortment of:
# - Converter procs.
# - Names of stored converters.
# - Nested converter lists.
#
# Examples:
#   numeric_converters = [:integer, :float]
#   date_converters = [:date, :date_time]
#   [numeric_converters, strip_converter]
#   [strip_converter, date_converters, :float]
#
# Like a converter proc, a converter list may be named and stored in either
# \CSV::Converters or CSV::HeaderConverters:
#   CSV::Converters[:custom] = [strip_converter, date_converters, :float]
#   CSV::HeaderConverters[:custom] = [:downcase, :symbol]
#
# There are two built-in converter lists:
#   CSV::Converters[:numeric] # => [:integer, :float]
#   CSV::Converters[:all] # => [:date_time, :numeric]
#
# ==== Field \Converters
#
# With no conversion, all parsed fields in all rows become Strings:
#   string = "foo,0\nbar,1\nbaz,2\n"
#   ary = CSV.parse(string)
#   ary # => # => [["foo", "0"], ["bar", "1"], ["baz", "2"]]
#
# When you specify a field converter, each parsed field is passed to the converter;
# its return value becomes the stored value for the field.
# A converter might, for example, convert an integer embedded in a \String
# into a true \Integer.
# (In fact, that's what built-in field converter +:integer+ does.)
#
# There are three ways to use field \converters.
#
# - Using option {converters}[#class-CSV-label-Option+converters] with a parsing method:
#     ary = CSV.parse(string, converters: :integer)
#     ary # => [0, 1, 2] # => [["foo", 0], ["bar", 1], ["baz", 2]]
# - Using option {converters}[#class-CSV-label-Option+converters] with a new \CSV instance:
#     csv = CSV.new(string, converters: :integer)
#     # Field converters in effect:
#     csv.converters # => [:integer]
#     csv.read # => [["foo", 0], ["bar", 1], ["baz", 2]]
# - Using method #convert to add a field converter to a \CSV instance:
#     csv = CSV.new(string)
#     # Add a converter.
#     csv.convert(:integer)
#     csv.converters # => [:integer]
#     csv.read # => [["foo", 0], ["bar", 1], ["baz", 2]]
#
# Installing a field converter does not affect already-read rows:
#   csv = CSV.new(string)
#   csv.shift # => ["foo", "0"]
#   # Add a converter.
#   csv.convert(:integer)
#   csv.converters # => [:integer]
#   csv.read # => [["bar", 1], ["baz", 2]]
#
# There are additional built-in \converters, and custom \converters are also supported.
#
# ===== Built-In Field \Converters
#
# The built-in field converters are in \Hash CSV::Converters:
# - Each key is a field converter name.
# - Each value is one of:
#   - A \Proc field converter.
#   - An \Array of field converter names.
#
# Display:
#   CSV::Converters.each_pair do |name, value|
#     if value.kind_of?(Proc)
#       p [name, value.class]
#     else
#       p [name, value]
#     end
#   end
# Output:
#   [:integer, Proc]
#   [:float, Proc]
#   [:numeric, [:integer, :float]]
#   [:date, Proc]
#   [:date_time, Proc]
#   [:all, [:date_time, :numeric]]
#
# Each of these converters transcodes values to UTF-8 before attempting conversion.
# If a value cannot be transcoded to UTF-8 the conversion will
# fail and the value will remain unconverted.
#
# Converter +:integer+ converts each field that Integer() accepts:
#   data = '0,1,2,x'
#   # Without the converter
#   csv = CSV.parse_line(data)
#   csv # => ["0", "1", "2", "x"]
#   # With the converter
#   csv = CSV.parse_line(data, converters: :integer)
#   csv # => [0, 1, 2, "x"]
#
# Converter +:float+ converts each field that Float() accepts:
#   data = '1.0,3.14159,x'
#   # Without the converter
#   csv = CSV.parse_line(data)
#   csv # => ["1.0", "3.14159", "x"]
#   # With the converter
#   csv = CSV.parse_line(data, converters: :float)
#   csv # => [1.0, 3.14159, "x"]
#
# Converter +:numeric+ converts with both +:integer+ and +:float+..
#
# Converter +:date+ converts each field that Date::parse accepts:
#   data = '2001-02-03,x'
#   # Without the converter
#   csv = CSV.parse_line(data)
#   csv # => ["2001-02-03", "x"]
#   # With the converter
#   csv = CSV.parse_line(data, converters: :date)
#   csv # => [#<Date: 2001-02-03 ((2451944j,0s,0n),+0s,2299161j)>, "x"]
#
# Converter +:date_time+ converts each field that DateTime::parse accepts:
#   data = '2020-05-07T14:59:00-05:00,x'
#   # Without the converter
#   csv = CSV.parse_line(data)
#   csv # => ["2020-05-07T14:59:00-05:00", "x"]
#   # With the converter
#   csv = CSV.parse_line(data, converters: :date_time)
#   csv # => [#<DateTime: 2020-05-07T14:59:00-05:00 ((2458977j,71940s,0n),-18000s,2299161j)>, "x"]
#
# Converter +:numeric+ converts with both +:date_time+ and +:numeric+..
#
# As seen above, method #convert adds \converters to a \CSV instance,
# and method #converters returns an \Array of the \converters in effect:
#   csv = CSV.new('0,1,2')
#   csv.converters # => []
#   csv.convert(:integer)
#   csv.converters # => [:integer]
#   csv.convert(:date)
#   csv.converters # => [:integer, :date]
#
# ===== Custom Field \Converters
#
# You can define a custom field converter:
#   strip_converter = proc {|field| field.strip }
#   string = " foo , 0 \n bar , 1 \n baz , 2 \n"
#   array = CSV.parse(string, converters: strip_converter)
#   array # => [["foo", "0"], ["bar", "1"], ["baz", "2"]]
# You can register the converter in \Converters \Hash,
# which allows you to refer to it by name:
#   CSV::Converters[:strip] = strip_converter
#   string = " foo , 0 \n bar , 1 \n baz , 2 \n"
#   array = CSV.parse(string, converters: :strip)
#   array # => [["foo", "0"], ["bar", "1"], ["baz", "2"]]
#
# ==== Header \Converters
#
# Header converters operate only on headers (and not on other rows).
#
# There are three ways to use header \converters;
# these examples use built-in header converter +:downcase+,
# which downcases each parsed header.
#
# - Option +header_converters+ with a singleton parsing method:
#     string = "Name,Count\nFoo,0\n,Bar,1\nBaz,2"
#     tbl = CSV.parse(string, headers: true, header_converters: :downcase)
#     tbl.class # => CSV::Table
#     tbl.headers # => ["name", "count"]
#
# - Option +header_converters+ with a new \CSV instance:
#     csv = CSV.new(string, header_converters: :downcase)
#     # Header converters in effect:
#     csv.header_converters # => [:downcase]
#     tbl = CSV.parse(string, headers: true)
#     tbl.headers # => ["Name", "Count"]
#
# - Method #header_convert adds a header converter to a \CSV instance:
#     csv = CSV.new(string)
#     # Add a header converter.
#     csv.header_convert(:downcase)
#     csv.header_converters # => [:downcase]
#     tbl = CSV.parse(string, headers: true)
#     tbl.headers # => ["Name", "Count"]
#
# ===== Built-In Header \Converters
#
# The built-in header \converters are in \Hash CSV::HeaderConverters.
# The keys there are the names of the \converters:
#   CSV::HeaderConverters.keys # => [:downcase, :symbol]
#
# Converter +:downcase+ converts each header by downcasing it:
#   string = "Name,Count\nFoo,0\n,Bar,1\nBaz,2"
#   tbl = CSV.parse(string, headers: true, header_converters: :downcase)
#   tbl.class # => CSV::Table
#   tbl.headers # => ["name", "count"]
#
# Converter +:symbol+ converts each header by making it into a \Symbol:
#   string = "Name,Count\nFoo,0\n,Bar,1\nBaz,2"
#   tbl = CSV.parse(string, headers: true, header_converters: :symbol)
#   tbl.headers # => [:name, :count]
# Details:
# - Strips leading and trailing whitespace.
# - Downcases the header.
# - Replaces embedded spaces with underscores.
# - Removes non-word characters.
# - Makes the string into a \Symbol.
#
# ===== Custom Header \Converters
#
# You can define a custom header converter:
#   upcase_converter = proc {|header| header.upcase }
#   string = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
#   table = CSV.parse(string, headers: true, header_converters: upcase_converter)
#   table # => #<CSV::Table mode:col_or_row row_count:4>
#   table.headers # => ["NAME", "VALUE"]
# You can register the converter in \HeaderConverters \Hash,
# which allows you to refer to it by name:
#   CSV::HeaderConverters[:upcase] = upcase_converter
#   table = CSV.parse(string, headers: true, header_converters: :upcase)
#   table # => #<CSV::Table mode:col_or_row row_count:4>
#   table.headers # => ["NAME", "VALUE"]
#
# ===== Write \Converters
#
# When you specify a write converter for generating \CSV,
# each field to be written is passed to the converter;
# its return value becomes the new value for the field.
# A converter might, for example, strip whitespace from a field.
#
# Using no write converter (all fields unmodified):
#   output_string = CSV.generate do |csv|
#     csv << [' foo ', 0]
#     csv << [' bar ', 1]
#     csv << [' baz ', 2]
#   end
#   output_string # => " foo ,0\n bar ,1\n baz ,2\n"
# Using option +write_converters+ with two custom write converters:
#   strip_converter = proc {|field| field.respond_to?(:strip) ? field.strip : field }
#   upcase_converter = proc {|field| field.respond_to?(:upcase) ? field.upcase : field }
#   write_converters = [strip_converter, upcase_converter]
#   output_string = CSV.generate(write_converters: write_converters) do |csv|
#     csv << [' foo ', 0]
#     csv << [' bar ', 1]
#     csv << [' baz ', 2]
#   end
#   output_string # => "FOO,0\nBAR,1\nBAZ,2\n"
#
# === Character Encodings (M17n or Multilingualization)
#
# This new CSV parser is m17n savvy.  The parser works in the Encoding of the IO
# or String object being read from or written to. Your data is never transcoded
# (unless you ask Ruby to transcode it for you) and will literally be parsed in
# the Encoding it is in. Thus CSV will return Arrays or Rows of Strings in the
# Encoding of your data. This is accomplished by transcoding the parser itself
# into your Encoding.
#
# Some transcoding must take place, of course, to accomplish this multiencoding
# support. For example, <tt>:col_sep</tt>, <tt>:row_sep</tt>, and
# <tt>:quote_char</tt> must be transcoded to match your data.  Hopefully this
# makes the entire process feel transparent, since CSV's defaults should just
# magically work for your data. However, you can set these values manually in
# the target Encoding to avoid the translation.
#
# It's also important to note that while all of CSV's core parser is now
# Encoding agnostic, some features are not. For example, the built-in
# converters will try to transcode data to UTF-8 before making conversions.
# Again, you can provide custom converters that are aware of your Encodings to
# avoid this translation. It's just too hard for me to support native
# conversions in all of Ruby's Encodings.
#
# Anyway, the practical side of this is simple: make sure IO and String objects
# passed into CSV have the proper Encoding set and everything should just work.
# CSV methods that allow you to open IO objects (CSV::foreach(), CSV::open(),
# CSV::read(), and CSV::readlines()) do allow you to specify the Encoding.
#
# One minor exception comes when generating CSV into a String with an Encoding
# that is not ASCII compatible. There's no existing data for CSV to use to
# prepare itself and thus you will probably need to manually specify the desired
# Encoding for most of those cases. It will try to guess using the fields in a
# row of output though, when using CSV::generate_line() or Array#to_csv().
#
# I try to point out any other Encoding issues in the documentation of methods
# as they come up.
#
# This has been tested to the best of my ability with all non-"dummy" Encodings
# Ruby ships with. However, it is brave new code and may have some bugs.
# Please feel free to {report}[mailto:james@grayproductions.net] any issues you
# find with it.
#
class CSV

  # The error thrown when the parser encounters illegal CSV formatting.
  class MalformedCSVError < RuntimeError
    attr_reader :line_number
    alias_method :lineno, :line_number
    def initialize(message, line_number)
      @line_number = line_number
      super("#{message} in line #{line_number}.")
    end
  end

  # The error thrown when the parser encounters invalid encoding in CSV.
  class InvalidEncodingError < MalformedCSVError
    attr_reader :encoding
    def initialize(encoding, line_number)
      @encoding = encoding
      super("Invalid byte sequence in #{encoding}", line_number)
    end
  end

  #
  # A FieldInfo Struct contains details about a field's position in the data
  # source it was read from.  CSV will pass this Struct to some blocks that make
  # decisions based on field structure.  See CSV.convert_fields() for an
  # example.
  #
  # <b><tt>index</tt></b>::  The zero-based index of the field in its row.
  # <b><tt>line</tt></b>::   The line of the data source this row is from.
  # <b><tt>header</tt></b>:: The header for the column, when available.
  # <b><tt>quoted?</tt></b>:: True or false, whether the original value is quoted or not.
  #
  FieldInfo = Struct.new(:index, :line, :header, :quoted?)

  # A Regexp used to find and convert some common Date formats.
  DateMatcher     = / \A(?: (\w+,?\s+)?\w+\s+\d{1,2},?\s+\d{2,4} |
                            \d{4}-\d{2}-\d{2} )\z /x
  # A Regexp used to find and convert some common DateTime formats.
  DateTimeMatcher =
    / \A(?: (\w+,?\s+)?\w+\s+\d{1,2}\s+\d{1,2}:\d{1,2}:\d{1,2},?\s+\d{2,4} |
            # ISO-8601 and RFC-3339 (space instead of T) recognized by DateTime.parse
            \d{4}-\d{2}-\d{2}
              (?:[T\s]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?(?:[+-]\d{2}(?::\d{2})|Z)?)?)?
        )\z /x

  # The encoding used by all converters.
  ConverterEncoding = Encoding.find("UTF-8")

  # A \Hash containing the names and \Procs for the built-in field converters.
  # See {Built-In Field Converters}[#class-CSV-label-Built-In+Field+Converters].
  #
  # This \Hash is intentionally left unfrozen, and may be extended with
  # custom field converters.
  # See {Custom Field Converters}[#class-CSV-label-Custom+Field+Converters].
  Converters  = {
    integer:   lambda { |f|
      Integer(f.encode(ConverterEncoding)) rescue f
    },
    float:     lambda { |f|
      Float(f.encode(ConverterEncoding)) rescue f
    },
    numeric:   [:integer, :float],
    date:      lambda { |f|
      begin
        e = f.encode(ConverterEncoding)
        e.match?(DateMatcher) ? Date.parse(e) : f
      rescue  # encoding conversion or date parse errors
        f
      end
    },
    date_time: lambda { |f|
      begin
        e = f.encode(ConverterEncoding)
        e.match?(DateTimeMatcher) ? DateTime.parse(e) : f
      rescue  # encoding conversion or date parse errors
        f
      end
    },
    all:       [:date_time, :numeric],
  }

  # A \Hash containing the names and \Procs for the built-in header converters.
  # See {Built-In Header Converters}[#class-CSV-label-Built-In+Header+Converters].
  #
  # This \Hash is intentionally left unfrozen, and may be extended with
  # custom field converters.
  # See {Custom Header Converters}[#class-CSV-label-Custom+Header+Converters].
  HeaderConverters = {
    downcase: lambda { |h| h.encode(ConverterEncoding).downcase },
    symbol:   lambda { |h|
      h.encode(ConverterEncoding).downcase.gsub(/[^\s\w]+/, "").strip.
                                           gsub(/\s+/, "_").to_sym
    },
    symbol_raw: lambda { |h| h.encode(ConverterEncoding).to_sym }
  }

  # Default values for method options.
  DEFAULT_OPTIONS = {
    # For both parsing and generating.
    col_sep:            ",",
    row_sep:            :auto,
    quote_char:         '"',
    # For parsing.
    field_size_limit:   nil,
    max_field_size:     nil,
    converters:         nil,
    unconverted_fields: nil,
    headers:            false,
    return_headers:     false,
    header_converters:  nil,
    skip_blanks:        false,
    skip_lines:         nil,
    liberal_parsing:    false,
    nil_value:          nil,
    empty_value:        "",
    strip:              false,
    # For generating.
    write_headers:      nil,
    quote_empty:        true,
    force_quotes:       false,
    write_converters:   nil,
    write_nil_value:    nil,
    write_empty_value:  "",
  }.freeze

  class << self
    # :call-seq:
    #   instance(string, **options)
    #   instance(io = $stdout, **options)
    #   instance(string, **options) {|csv| ... }
    #   instance(io = $stdout, **options) {|csv| ... }
    #
    # Creates or retrieves cached \CSV objects.
    # For arguments and options, see CSV.new.
    #
    # This API is not Ractor-safe.
    #
    # ---
    #
    # With no block given, returns a \CSV object.
    #
    # The first call to +instance+ creates and caches a \CSV object:
    #   s0 = 's0'
    #   csv0 = CSV.instance(s0)
    #   csv0.class # => CSV
    #
    # Subsequent calls to +instance+ with that _same_ +string+ or +io+
    # retrieve that same cached object:
    #   csv1 = CSV.instance(s0)
    #   csv1.class # => CSV
    #   csv1.equal?(csv0) # => true # Same CSV object
    #
    # A subsequent call to +instance+ with a _different_ +string+ or +io+
    # creates and caches a _different_ \CSV object.
    #   s1 = 's1'
    #   csv2 = CSV.instance(s1)
    #   csv2.equal?(csv0) # => false # Different CSV object
    #
    # All the cached objects remains available:
    #   csv3 = CSV.instance(s0)
    #   csv3.equal?(csv0) # true # Same CSV object
    #   csv4 = CSV.instance(s1)
    #   csv4.equal?(csv2) # true # Same CSV object
    #
    # ---
    #
    # When a block is given, calls the block with the created or retrieved
    # \CSV object; returns the block's return value:
    #   CSV.instance(s0) {|csv| :foo } # => :foo
    def instance(data = $stdout, **options)
      # create a _signature_ for this method call, data object and options
      sig = [data.object_id] +
            options.values_at(*DEFAULT_OPTIONS.keys)

      # fetch or create the instance for this signature
      @@instances ||= Hash.new
      instance = (@@instances[sig] ||= new(data, **options))

      if block_given?
        yield instance  # run block, if given, returning result
      else
        instance        # or return the instance
      end
    end

    # :call-seq:
    #   filter(in_string_or_io, **options) {|row| ... } -> array_of_arrays or csv_table
    #   filter(in_string_or_io, out_string_or_io, **options) {|row| ... } -> array_of_arrays or csv_table
    #   filter(**options) {|row| ... } -> array_of_arrays or csv_table
    #
    # - Parses \CSV from a source (\String, \IO stream, or ARGF).
    # - Calls the given block with each parsed row:
    #   - Without headers, each row is an \Array.
    #   - With headers, each row is a CSV::Row.
    # - Generates \CSV to an output (\String, \IO stream, or STDOUT).
    # - Returns the parsed source:
    #   - Without headers, an \Array of \Arrays.
    #   - With headers, a CSV::Table.
    #
    # When +in_string_or_io+ is given, but not +out_string_or_io+,
    # parses from the given +in_string_or_io+
    # and generates to STDOUT.
    #
    # \String input without headers:
    #
    #   in_string = "foo,0\nbar,1\nbaz,2"
    #   CSV.filter(in_string) do |row|
    #     row[0].upcase!
    #     row[1] = - row[1].to_i
    #   end # => [["FOO", 0], ["BAR", -1], ["BAZ", -2]]
    #
    # Output (to STDOUT):
    #
    #   FOO,0
    #   BAR,-1
    #   BAZ,-2
    #
    # \String input with headers:
    #
    #   in_string = "Name,Value\nfoo,0\nbar,1\nbaz,2"
    #   CSV.filter(in_string, headers: true) do |row|
    #     row[0].upcase!
    #     row[1] = - row[1].to_i
    #   end # => #<CSV::Table mode:col_or_row row_count:4>
    #
    # Output (to STDOUT):
    #
    #   Name,Value
    #   FOO,0
    #   BAR,-1
    #   BAZ,-2
    #
    # \IO stream input without headers:
    #
    #   File.write('t.csv', "foo,0\nbar,1\nbaz,2")
    #   File.open('t.csv') do |in_io|
    #     CSV.filter(in_io) do |row|
    #       row[0].upcase!
    #       row[1] = - row[1].to_i
    #     end
    #   end # => [["FOO", 0], ["BAR", -1], ["BAZ", -2]]
    #
    # Output (to STDOUT):
    #
    #   FOO,0
    #   BAR,-1
    #   BAZ,-2
    #
    # \IO stream input with headers:
    #
    #   File.write('t.csv', "Name,Value\nfoo,0\nbar,1\nbaz,2")
    #   File.open('t.csv') do |in_io|
    #     CSV.filter(in_io, headers: true) do |row|
    #       row[0].upcase!
    #       row[1] = - row[1].to_i
    #     end
    #   end # => #<CSV::Table mode:col_or_row row_count:4>
    #
    # Output (to STDOUT):
    #
    #   Name,Value
    #   FOO,0
    #   BAR,-1
    #   BAZ,-2
    #
    # When both +in_string_or_io+ and +out_string_or_io+ are given,
    # parses from +in_string_or_io+ and generates to +out_string_or_io+.
    #
    # \String output without headers:
    #
    #   in_string = "foo,0\nbar,1\nbaz,2"
    #   out_string = ''
    #   CSV.filter(in_string, out_string) do |row|
    #     row[0].upcase!
    #     row[1] = - row[1].to_i
    #   end # => [["FOO", 0], ["BAR", -1], ["BAZ", -2]]
    #   out_string # => "FOO,0\nBAR,-1\nBAZ,-2\n"
    #
    # \String output with headers:
    #
    #   in_string = "Name,Value\nfoo,0\nbar,1\nbaz,2"
    #   out_string = ''
    #   CSV.filter(in_string, out_string, headers: true) do |row|
    #     row[0].upcase!
    #     row[1] = - row[1].to_i
    #   end # => #<CSV::Table mode:col_or_row row_count:4>
    #   out_string # => "Name,Value\nFOO,0\nBAR,-1\nBAZ,-2\n"
    #
    # \IO stream output without headers:
    #
    #   in_string = "foo,0\nbar,1\nbaz,2"
    #   File.open('t.csv', 'w') do |out_io|
    #     CSV.filter(in_string, out_io) do |row|
    #       row[0].upcase!
    #       row[1] = - row[1].to_i
    #     end
    #   end # => [["FOO", 0], ["BAR", -1], ["BAZ", -2]]
    #   File.read('t.csv') # => "FOO,0\nBAR,-1\nBAZ,-2\n"
    #
    # \IO stream output with headers:
    #
    #   in_string = "Name,Value\nfoo,0\nbar,1\nbaz,2"
    #   File.open('t.csv', 'w') do |out_io|
    #     CSV.filter(in_string, out_io, headers: true) do |row|
    #       row[0].upcase!
    #       row[1] = - row[1].to_i
    #     end
    #   end # => #<CSV::Table mode:col_or_row row_count:4>
    #   File.read('t.csv') # => "Name,Value\nFOO,0\nBAR,-1\nBAZ,-2\n"
    #
    # When neither +in_string_or_io+ nor +out_string_or_io+ given,
    # parses from {ARGF}[rdoc-ref:ARGF]
    # and generates to STDOUT.
    #
    # Without headers:
    #
    #   # Put Ruby code into a file.
    #   ruby = <<-EOT
    #     require 'csv'
    #     CSV.filter do |row|
    #       row[0].upcase!
    #       row[1] = - row[1].to_i
    #     end
    #   EOT
    #   File.write('t.rb', ruby)
    #   # Put some CSV into a file.
    #   File.write('t.csv', "foo,0\nbar,1\nbaz,2")
    #   # Run the Ruby code with CSV filename as argument.
    #   system(Gem.ruby, "t.rb", "t.csv")
    #
    # Output (to STDOUT):
    #
    #   FOO,0
    #   BAR,-1
    #   BAZ,-2
    #
    # With headers:
    #
    #   # Put Ruby code into a file.
    #   ruby = <<-EOT
    #     require 'csv'
    #     CSV.filter(headers: true) do |row|
    #       row[0].upcase!
    #       row[1] = - row[1].to_i
    #     end
    #   EOT
    #   File.write('t.rb', ruby)
    #   # Put some CSV into a file.
    #   File.write('t.csv', "Name,Value\nfoo,0\nbar,1\nbaz,2")
    #   # Run the Ruby code with CSV filename as argument.
    #   system(Gem.ruby, "t.rb", "t.csv")
    #
    # Output (to STDOUT):
    #
    #   Name,Value
    #   FOO,0
    #   BAR,-1
    #   BAZ,-2
    #
    # Arguments:
    #
    # * Argument +in_string_or_io+ must be a \String or an \IO stream.
    # * Argument +out_string_or_io+ must be a \String or an \IO stream.
    # * Arguments <tt>**options</tt> must be keyword options.
    #   See {Options for Parsing}[#class-CSV-label-Options+for+Parsing].
    def filter(input=nil, output=nil, **options)
      # parse options for input, output, or both
      in_options, out_options = Hash.new, {row_sep: InputRecordSeparator.value}
      options.each do |key, value|
        case key
        when /\Ain(?:put)?_(.+)\Z/
          in_options[$1.to_sym] = value
        when /\Aout(?:put)?_(.+)\Z/
          out_options[$1.to_sym] = value
        else
          in_options[key]  = value
          out_options[key] = value
        end
      end

      # build input and output wrappers
      input  = new(input  || ARGF, **in_options)
      output = new(output || $stdout, **out_options)

      # process headers
      need_manual_header_output =
        (in_options[:headers] and
         out_options[:headers] == true and
         out_options[:write_headers])
      if need_manual_header_output
        first_row = input.shift
        if first_row
          if first_row.is_a?(Row)
            headers = first_row.headers
            yield headers
            output << headers
          end
          yield first_row
          output << first_row
        end
      end

      # read, yield, write
      input.each do |row|
        yield row
        output << row
      end
    end

    #
    # :call-seq:
    #   foreach(path_or_io, mode='r', **options) {|row| ... )
    #   foreach(path_or_io, mode='r', **options) -> new_enumerator
    #
    # Calls the block with each row read from source +path_or_io+.
    #
    # \Path input without headers:
    #
    #   string = "foo,0\nbar,1\nbaz,2\n"
    #   in_path = 't.csv'
    #   File.write(in_path, string)
    #   CSV.foreach(in_path) {|row| p row }
    #
    # Output:
    #
    #   ["foo", "0"]
    #   ["bar", "1"]
    #   ["baz", "2"]
    #
    # \Path input with headers:
    #
    #   string = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
    #   in_path = 't.csv'
    #   File.write(in_path, string)
    #   CSV.foreach(in_path, headers: true) {|row| p row }
    #
    # Output:
    #
    #   <CSV::Row "Name":"foo" "Value":"0">
    #   <CSV::Row "Name":"bar" "Value":"1">
    #   <CSV::Row "Name":"baz" "Value":"2">
    #
    # \IO stream input without headers:
    #
    #   string = "foo,0\nbar,1\nbaz,2\n"
    #   path = 't.csv'
    #   File.write(path, string)
    #   File.open('t.csv') do |in_io|
    #     CSV.foreach(in_io) {|row| p row }
    #   end
    #
    # Output:
    #
    #   ["foo", "0"]
    #   ["bar", "1"]
    #   ["baz", "2"]
    #
    # \IO stream input with headers:
    #
    #   string = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
    #   path = 't.csv'
    #   File.write(path, string)
    #   File.open('t.csv') do |in_io|
    #     CSV.foreach(in_io, headers: true) {|row| p row }
    #   end
    #
    # Output:
    #
    #   <CSV::Row "Name":"foo" "Value":"0">
    #   <CSV::Row "Name":"bar" "Value":"1">
    #   <CSV::Row "Name":"baz" "Value":"2">
    #
    # With no block given, returns an \Enumerator:
    #
    #   string = "foo,0\nbar,1\nbaz,2\n"
    #   path = 't.csv'
    #   File.write(path, string)
    #   CSV.foreach(path) # => #<Enumerator: CSV:foreach("t.csv", "r")>
    #
    # Arguments:
    # * Argument +path_or_io+ must be a file path or an \IO stream.
    # * Argument +mode+, if given, must be a \File mode.
    #   See {Access Modes}[rdoc-ref:File@Access+Modes].
    # * Arguments <tt>**options</tt> must be keyword options.
    #   See {Options for Parsing}[#class-CSV-label-Options+for+Parsing].
    # * This method optionally accepts an additional <tt>:encoding</tt> option
    #   that you can use to specify the Encoding of the data read from +path+ or +io+.
    #   You must provide this unless your data is in the encoding
    #   given by <tt>Encoding::default_external</tt>.
    #   Parsing will use this to determine how to parse the data.
    #   You may provide a second Encoding to
    #   have the data transcoded as it is read. For example,
    #     encoding: 'UTF-32BE:UTF-8'
    #   would read +UTF-32BE+ data from the file
    #   but transcode it to +UTF-8+ before parsing.
    def foreach(path, mode="r", **options, &block)
      return to_enum(__method__, path, mode, **options) unless block_given?
      open(path, mode, **options) do |csv|
        csv.each(&block)
      end
    end

    #
    # :call-seq:
    #   generate(csv_string, **options) {|csv| ... }
    #   generate(**options) {|csv| ... }
    #
    # * Argument +csv_string+, if given, must be a \String object;
    #   defaults to a new empty \String.
    # * Arguments +options+, if given, should be generating options.
    #   See {Options for Generating}[#class-CSV-label-Options+for+Generating].
    #
    # ---
    #
    # Creates a new \CSV object via <tt>CSV.new(csv_string, **options)</tt>;
    # calls the block with the \CSV object, which the block may modify;
    # returns the \String generated from the \CSV object.
    #
    # Note that a passed \String *is* modified by this method.
    # Pass <tt>csv_string</tt>.dup if the \String must be preserved.
    #
    # This method has one additional option: <tt>:encoding</tt>,
    # which sets the base Encoding for the output if no no +str+ is specified.
    # CSV needs this hint if you plan to output non-ASCII compatible data.
    #
    # ---
    #
    # Add lines:
    #   input_string = "foo,0\nbar,1\nbaz,2\n"
    #   output_string = CSV.generate(input_string) do |csv|
    #     csv << ['bat', 3]
    #     csv << ['bam', 4]
    #   end
    #   output_string # => "foo,0\nbar,1\nbaz,2\nbat,3\nbam,4\n"
    #   input_string # => "foo,0\nbar,1\nbaz,2\nbat,3\nbam,4\n"
    #   output_string.equal?(input_string) # => true # Same string, modified
    #
    # Add lines into new string, preserving old string:
    #   input_string = "foo,0\nbar,1\nbaz,2\n"
    #   output_string = CSV.generate(input_string.dup) do |csv|
    #     csv << ['bat', 3]
    #     csv << ['bam', 4]
    #   end
    #   output_string # => "foo,0\nbar,1\nbaz,2\nbat,3\nbam,4\n"
    #   input_string # => "foo,0\nbar,1\nbaz,2\n"
    #   output_string.equal?(input_string) # => false # Different strings
    #
    # Create lines from nothing:
    #   output_string = CSV.generate do |csv|
    #     csv << ['foo', 0]
    #     csv << ['bar', 1]
    #     csv << ['baz', 2]
    #   end
    #   output_string # => "foo,0\nbar,1\nbaz,2\n"
    #
    # ---
    #
    # Raises an exception if +csv_string+ is not a \String object:
    #   # Raises TypeError (no implicit conversion of Integer into String)
    #   CSV.generate(0)
    #
    def generate(str=nil, **options)
      encoding = options[:encoding]
      # add a default empty String, if none was given
      if str
        str = StringIO.new(str)
        str.seek(0, IO::SEEK_END)
        str.set_encoding(encoding) if encoding
      else
        str = +""
        str.force_encoding(encoding) if encoding
      end
      csv = new(str, **options) # wrap
      yield csv         # yield for appending
      csv.string        # return final String
    end

    # :call-seq:
    #   CSV.generate_line(ary)
    #   CSV.generate_line(ary, **options)
    #
    # Returns the \String created by generating \CSV from +ary+
    # using the specified +options+.
    #
    # Argument +ary+ must be an \Array.
    #
    # Special options:
    # * Option <tt>:row_sep</tt> defaults to <tt>"\n"> on Ruby 3.0 or later
    #   and <tt>$INPUT_RECORD_SEPARATOR</tt> (<tt>$/</tt>) otherwise.:
    #     $INPUT_RECORD_SEPARATOR # => "\n"
    # * This method accepts an additional option, <tt>:encoding</tt>, which sets the base
    #   Encoding for the output. This method will try to guess your Encoding from
    #   the first non-+nil+ field in +row+, if possible, but you may need to use
    #   this parameter as a backup plan.
    #
    # For other +options+,
    # see {Options for Generating}[#class-CSV-label-Options+for+Generating].
    #
    # ---
    #
    # Returns the \String generated from an \Array:
    #   CSV.generate_line(['foo', '0']) # => "foo,0\n"
    #
    # ---
    #
    # Raises an exception if +ary+ is not an \Array:
    #   # Raises NoMethodError (undefined method `find' for :foo:Symbol)
    #   CSV.generate_line(:foo)
    #
    def generate_line(row, **options)
      options = {row_sep: InputRecordSeparator.value}.merge(options)
      str = +""
      if options[:encoding]
        str.force_encoding(options[:encoding])
      else
        fallback_encoding = nil
        output_encoding = nil
        row.each do |field|
          next unless field.is_a?(String)
          fallback_encoding ||= field.encoding
          next if field.ascii_only?
          output_encoding = field.encoding
          break
        end
        output_encoding ||= fallback_encoding
        if output_encoding
          str.force_encoding(output_encoding)
        end
      end
      (new(str, **options) << row).string
    end

    # :call-seq:
    #   CSV.generate_lines(rows)
    #   CSV.generate_lines(rows, **options)
    #
    # Returns the \String created by generating \CSV from
    # using the specified +options+.
    #
    # Argument +rows+ must be an \Array of row. Row is \Array of \String or \CSV::Row.
    #
    # Special options:
    # * Option <tt>:row_sep</tt> defaults to <tt>"\n"</tt> on Ruby 3.0 or later
    #   and <tt>$INPUT_RECORD_SEPARATOR</tt> (<tt>$/</tt>) otherwise.:
    #     $INPUT_RECORD_SEPARATOR # => "\n"
    # * This method accepts an additional option, <tt>:encoding</tt>, which sets the base
    #   Encoding for the output. This method will try to guess your Encoding from
    #   the first non-+nil+ field in +row+, if possible, but you may need to use
    #   this parameter as a backup plan.
    #
    # For other +options+,
    # see {Options for Generating}[#class-CSV-label-Options+for+Generating].
    #
    # ---
    #
    # Returns the \String generated from an
    #   CSV.generate_lines([['foo', '0'], ['bar', '1'], ['baz', '2']]) # => "foo,0\nbar,1\nbaz,2\n"
    #
    # ---
    #
    # Raises an exception
    #   # Raises NoMethodError (undefined method `each' for :foo:Symbol)
    #   CSV.generate_lines(:foo)
    #
    def generate_lines(rows, **options)
      self.generate(**options) do |csv|
        rows.each do |row|
          csv << row
        end
      end
    end

    #
    # :call-seq:
    #   open(file_path, mode = "rb", **options ) -> new_csv
    #   open(io, mode = "rb", **options ) -> new_csv
    #   open(file_path, mode = "rb", **options ) { |csv| ... } -> object
    #   open(io, mode = "rb", **options ) { |csv| ... } -> object
    #
    # possible options elements:
    #   keyword form:
    #     :invalid => nil      # raise error on invalid byte sequence (default)
    #     :invalid => :replace # replace invalid byte sequence
    #     :undef => :replace   # replace undefined conversion
    #     :replace => string   # replacement string ("?" or "\uFFFD" if not specified)
    #
    # * Argument +path+, if given, must be the path to a file.
    # :include: ../doc/csv/arguments/io.rdoc
    # * Argument +mode+, if given, must be a \File mode.
    #   See {Access Modes}[rdoc-ref:File@Access+Modes].
    # * Arguments <tt>**options</tt> must be keyword options.
    #   See {Options for Generating}[#class-CSV-label-Options+for+Generating].
    # * This method optionally accepts an additional <tt>:encoding</tt> option
    #   that you can use to specify the Encoding of the data read from +path+ or +io+.
    #   You must provide this unless your data is in the encoding
    #   given by <tt>Encoding::default_external</tt>.
    #   Parsing will use this to determine how to parse the data.
    #   You may provide a second Encoding to
    #   have the data transcoded as it is read. For example,
    #     encoding: 'UTF-32BE:UTF-8'
    #   would read +UTF-32BE+ data from the file
    #   but transcode it to +UTF-8+ before parsing.
    #
    # ---
    #
    # These examples assume prior execution of:
    #   string = "foo,0\nbar,1\nbaz,2\n"
    #   path = 't.csv'
    #   File.write(path, string)
    #
    # ---
    #
    # With no block given, returns a new \CSV object.
    #
    # Create a \CSV object using a file path:
    #   csv = CSV.open(path)
    #   csv # => #<CSV io_type:File io_path:"t.csv" encoding:UTF-8 lineno:0 col_sep:"," row_sep:"\n" quote_char:"\"">
    #
    # Create a \CSV object using an open \File:
    #   csv = CSV.open(File.open(path))
    #   csv # => #<CSV io_type:File io_path:"t.csv" encoding:UTF-8 lineno:0 col_sep:"," row_sep:"\n" quote_char:"\"">
    #
    # ---
    #
    # With a block given, calls the block with the created \CSV object;
    # returns the block's return value:
    #
    # Using a file path:
    #   csv = CSV.open(path) {|csv| p csv}
    #   csv # => #<CSV io_type:File io_path:"t.csv" encoding:UTF-8 lineno:0 col_sep:"," row_sep:"\n" quote_char:"\"">
    # Output:
    #   #<CSV io_type:File io_path:"t.csv" encoding:UTF-8 lineno:0 col_sep:"," row_sep:"\n" quote_char:"\"">
    #
    # Using an open \File:
    #   csv = CSV.open(File.open(path)) {|csv| p csv}
    #   csv # => #<CSV io_type:File io_path:"t.csv" encoding:UTF-8 lineno:0 col_sep:"," row_sep:"\n" quote_char:"\"">
    # Output:
    #   #<CSV io_type:File io_path:"t.csv" encoding:UTF-8 lineno:0 col_sep:"," row_sep:"\n" quote_char:"\"">
    #
    # ---
    #
    # Raises an exception if the argument is not a \String object or \IO object:
    #   # Raises TypeError (no implicit conversion of Symbol into String)
    #   CSV.open(:foo)
    def open(filename, mode="r", **options)
      # wrap a File opened with the remaining +args+ with no newline
      # decorator
      file_opts = options.dup
      unless file_opts.key?(:newline)
        file_opts[:universal_newline] ||= false
      end
      options.delete(:invalid)
      options.delete(:undef)
      options.delete(:replace)
      options.delete_if {|k, _| /newline\z/.match?(k)}

      begin
        f = File.open(filename, mode, **file_opts)
      rescue ArgumentError => e
        raise unless /needs binmode/.match?(e.message) and mode == "r"
        mode = "rb"
        file_opts = {encoding: Encoding.default_external}.merge(file_opts)
        retry
      end
      begin
        csv = new(f, **options)
      rescue Exception
        f.close
        raise
      end

      # handle blocks like Ruby's open(), not like the CSV library
      if block_given?
        begin
          yield csv
        ensure
          csv.close
        end
      else
        csv
      end
    end

    #
    # :call-seq:
    #   parse(string) -> array_of_arrays
    #   parse(io) -> array_of_arrays
    #   parse(string, headers: ..., **options) -> csv_table
    #   parse(io, headers: ..., **options) -> csv_table
    #   parse(string, **options) {|row| ... }
    #   parse(io, **options) {|row| ... }
    #
    # Parses +string+ or +io+ using the specified +options+.
    #
    # - Argument +string+ should be a \String object;
    #   it will be put into a new StringIO object positioned at the beginning.
    # :include: ../doc/csv/arguments/io.rdoc
    # - Argument +options+: see {Options for Parsing}[#class-CSV-label-Options+for+Parsing]
    #
    # ====== Without Option +headers+
    #
    # Without {option +headers+}[#class-CSV-label-Option+headers] case.
    #
    # These examples assume prior execution of:
    #   string = "foo,0\nbar,1\nbaz,2\n"
    #   path = 't.csv'
    #   File.write(path, string)
    #
    # ---
    #
    # With no block given, returns an \Array of Arrays formed from the source.
    #
    # Parse a \String:
    #   a_of_a = CSV.parse(string)
    #   a_of_a # => [["foo", "0"], ["bar", "1"], ["baz", "2"]]
    #
    # Parse an open \File:
    #   a_of_a = File.open(path) do |file|
    #     CSV.parse(file)
    #   end
    #   a_of_a # => [["foo", "0"], ["bar", "1"], ["baz", "2"]]
    #
    # ---
    #
    # With a block given, calls the block with each parsed row:
    #
    # Parse a \String:
    #   CSV.parse(string) {|row| p row }
    #
    # Output:
    #   ["foo", "0"]
    #   ["bar", "1"]
    #   ["baz", "2"]
    #
    # Parse an open \File:
    #   File.open(path) do |file|
    #     CSV.parse(file) {|row| p row }
    #   end
    #
    # Output:
    #   ["foo", "0"]
    #   ["bar", "1"]
    #   ["baz", "2"]
    #
    # ====== With Option +headers+
    #
    # With {option +headers+}[#class-CSV-label-Option+headers] case.
    #
    # These examples assume prior execution of:
    #   string = "Name,Count\nfoo,0\nbar,1\nbaz,2\n"
    #   path = 't.csv'
    #   File.write(path, string)
    #
    # ---
    #
    # With no block given, returns a CSV::Table object formed from the source.
    #
    # Parse a \String:
    #   csv_table = CSV.parse(string, headers: ['Name', 'Count'])
    #   csv_table # => #<CSV::Table mode:col_or_row row_count:5>
    #
    # Parse an open \File:
    #   csv_table = File.open(path) do |file|
    #     CSV.parse(file, headers: ['Name', 'Count'])
    #   end
    #   csv_table # => #<CSV::Table mode:col_or_row row_count:4>
    #
    # ---
    #
    # With a block given, calls the block with each parsed row,
    # which has been formed into a CSV::Row object:
    #
    # Parse a \String:
    #   CSV.parse(string, headers: ['Name', 'Count']) {|row| p row }
    #
    # Output:
    #   # <CSV::Row "Name":"foo" "Count":"0">
    #   # <CSV::Row "Name":"bar" "Count":"1">
    #   # <CSV::Row "Name":"baz" "Count":"2">
    #
    # Parse an open \File:
    #   File.open(path) do |file|
    #     CSV.parse(file, headers: ['Name', 'Count']) {|row| p row }
    #   end
    #
    # Output:
    #   # <CSV::Row "Name":"foo" "Count":"0">
    #   # <CSV::Row "Name":"bar" "Count":"1">
    #   # <CSV::Row "Name":"baz" "Count":"2">
    #
    # ---
    #
    # Raises an exception if the argument is not a \String object or \IO object:
    #   # Raises NoMethodError (undefined method `close' for :foo:Symbol)
    #   CSV.parse(:foo)
    def parse(str, **options, &block)
      csv = new(str, **options)

      return csv.each(&block) if block_given?

      # slurp contents, if no block is given
      begin
        csv.read
      ensure
        csv.close
      end
    end

    # :call-seq:
    #   CSV.parse_line(string) -> new_array or nil
    #   CSV.parse_line(io) -> new_array or nil
    #   CSV.parse_line(string, **options) -> new_array or nil
    #   CSV.parse_line(io, **options) -> new_array or nil
    #   CSV.parse_line(string, headers: true, **options) -> csv_row or nil
    #   CSV.parse_line(io, headers: true, **options) -> csv_row or nil
    #
    # Returns the data created by parsing the first line of +string+ or +io+
    # using the specified +options+.
    #
    # - Argument +string+ should be a \String object;
    #   it will be put into a new StringIO object positioned at the beginning.
    # :include: ../doc/csv/arguments/io.rdoc
    # - Argument +options+: see {Options for Parsing}[#class-CSV-label-Options+for+Parsing]
    #
    # ====== Without Option +headers+
    #
    # Without option +headers+, returns the first row as a new \Array.
    #
    # These examples assume prior execution of:
    #   string = "foo,0\nbar,1\nbaz,2\n"
    #   path = 't.csv'
    #   File.write(path, string)
    #
    # Parse the first line from a \String object:
    #   CSV.parse_line(string) # => ["foo", "0"]
    #
    # Parse the first line from a File object:
    #   File.open(path) do |file|
    #     CSV.parse_line(file) # => ["foo", "0"]
    #   end # => ["foo", "0"]
    #
    # Returns +nil+ if the argument is an empty \String:
    #   CSV.parse_line('') # => nil
    #
    # ====== With Option +headers+
    #
    # With {option +headers+}[#class-CSV-label-Option+headers],
    # returns the first row as a CSV::Row object.
    #
    # These examples assume prior execution of:
    #   string = "Name,Count\nfoo,0\nbar,1\nbaz,2\n"
    #   path = 't.csv'
    #   File.write(path, string)
    #
    # Parse the first line from a \String object:
    #   CSV.parse_line(string, headers: true) # => #<CSV::Row "Name":"foo" "Count":"0">
    #
    # Parse the first line from a File object:
    #   File.open(path) do |file|
    #     CSV.parse_line(file, headers: true)
    #   end # => #<CSV::Row "Name":"foo" "Count":"0">
    #
    # ---
    #
    # Raises an exception if the argument is +nil+:
    #   # Raises ArgumentError (Cannot parse nil as CSV):
    #   CSV.parse_line(nil)
    #
    def parse_line(line, **options)
      new(line, **options).each.first
    end

    #
    # :call-seq:
    #   read(source, **options) -> array_of_arrays
    #   read(source, headers: true, **options) -> csv_table
    #
    # Opens the given +source+ with the given +options+ (see CSV.open),
    # reads the source (see CSV#read), and returns the result,
    # which will be either an \Array of Arrays or a CSV::Table.
    #
    # Without headers:
    #   string = "foo,0\nbar,1\nbaz,2\n"
    #   path = 't.csv'
    #   File.write(path, string)
    #   CSV.read(path) # => [["foo", "0"], ["bar", "1"], ["baz", "2"]]
    #
    # With headers:
    #   string = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
    #   path = 't.csv'
    #   File.write(path, string)
    #   CSV.read(path, headers: true) # => #<CSV::Table mode:col_or_row row_count:4>
    def read(path, **options)
      open(path, **options) { |csv| csv.read }
    end

    # :call-seq:
    #   CSV.readlines(source, **options)
    #
    # Alias for CSV.read.
    def readlines(path, **options)
      read(path, **options)
    end

    # :call-seq:
    #   CSV.table(source, **options)
    #
    # Calls CSV.read with +source+, +options+, and certain default options:
    # - +headers+: +true+
    # - +converters+: +:numeric+
    # - +header_converters+: +:symbol+
    #
    # Returns a CSV::Table object.
    #
    # Example:
    #   string = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
    #   path = 't.csv'
    #   File.write(path, string)
    #   CSV.table(path) # => #<CSV::Table mode:col_or_row row_count:4>
    def table(path, **options)
      default_options = {
        headers:           true,
        converters:        :numeric,
        header_converters: :symbol,
      }
      options = default_options.merge(options)
      read(path, **options)
    end
  end

  # :call-seq:
  #   CSV.new(string)
  #   CSV.new(io)
  #   CSV.new(string, **options)
  #   CSV.new(io, **options)
  #
  # Returns the new \CSV object created using +string+ or +io+
  # and the specified +options+.
  #
  # - Argument +string+ should be a \String object;
  #   it will be put into a new StringIO object positioned at the beginning.
  # :include: ../doc/csv/arguments/io.rdoc
  # - Argument +options+: See:
  #   * {Options for Parsing}[#class-CSV-label-Options+for+Parsing]
  #   * {Options for Generating}[#class-CSV-label-Options+for+Generating]
  #   For performance reasons, the options cannot be overridden
  #   in a \CSV object, so those specified here will endure.
  #
  # In addition to the \CSV instance methods, several \IO methods are delegated.
  # See {Delegated Methods}[#class-CSV-label-Delegated+Methods].
  #
  # ---
  #
  # Create a \CSV object from a \String object:
  #   csv = CSV.new('foo,0')
  #   csv # => #<CSV io_type:StringIO encoding:UTF-8 lineno:0 col_sep:"," row_sep:"\n" quote_char:"\"">
  #
  # Create a \CSV object from a \File object:
  #   File.write('t.csv', 'foo,0')
  #   csv = CSV.new(File.open('t.csv'))
  #   csv # => #<CSV io_type:File io_path:"t.csv" encoding:UTF-8 lineno:0 col_sep:"," row_sep:"\n" quote_char:"\"">
  #
  # ---
  #
  # Raises an exception if the argument is +nil+:
  #   # Raises ArgumentError (Cannot parse nil as CSV):
  #   CSV.new(nil)
  #
  def initialize(data,
                 col_sep: ",",
                 row_sep: :auto,
                 quote_char: '"',
                 field_size_limit: nil,
                 max_field_size: nil,
                 converters: nil,
                 unconverted_fields: nil,
                 headers: false,
                 return_headers: false,
                 write_headers: nil,
                 header_converters: nil,
                 skip_blanks: false,
                 force_quotes: false,
                 skip_lines: nil,
                 liberal_parsing: false,
                 internal_encoding: nil,
                 external_encoding: nil,
                 encoding: nil,
                 nil_value: nil,
                 empty_value: "",
                 strip: false,
                 quote_empty: true,
                 write_converters: nil,
                 write_nil_value: nil,
                 write_empty_value: "")
    raise ArgumentError.new("Cannot parse nil as CSV") if data.nil?

    if data.is_a?(String)
      if encoding
        if encoding.is_a?(String)
          data_external_encoding, data_internal_encoding = encoding.split(":", 2)
          if data_internal_encoding
            data = data.encode(data_internal_encoding, data_external_encoding)
          else
            data = data.dup.force_encoding(data_external_encoding)
          end
        else
          data = data.dup.force_encoding(encoding)
        end
      end
      @io = StringIO.new(data)
    else
      @io = data
    end
    @encoding = determine_encoding(encoding, internal_encoding)

    @base_fields_converter_options = {
      nil_value: nil_value,
      empty_value: empty_value,
    }
    @write_fields_converter_options = {
      nil_value: write_nil_value,
      empty_value: write_empty_value,
    }
    @initial_converters = converters
    @initial_header_converters = header_converters
    @initial_write_converters = write_converters

    if max_field_size.nil? and field_size_limit
      max_field_size = field_size_limit - 1
    end
    @parser_options = {
      column_separator: col_sep,
      row_separator: row_sep,
      quote_character: quote_char,
      max_field_size: max_field_size,
      unconverted_fields: unconverted_fields,
      headers: headers,
      return_headers: return_headers,
      skip_blanks: skip_blanks,
      skip_lines: skip_lines,
      liberal_parsing: liberal_parsing,
      encoding: @encoding,
      nil_value: nil_value,
      empty_value: empty_value,
      strip: strip,
    }
    @parser = nil
    @parser_enumerator = nil
    @eof_error = nil

    @writer_options = {
      encoding: @encoding,
      force_encoding: (not encoding.nil?),
      force_quotes: force_quotes,
      headers: headers,
      write_headers: write_headers,
      column_separator: col_sep,
      row_separator: row_sep,
      quote_character: quote_char,
      quote_empty: quote_empty,
    }

    @writer = nil
    writer if @writer_options[:write_headers]
  end

  # :call-seq:
  #   csv.col_sep -> string
  #
  # Returns the encoded column separator; used for parsing and writing;
  # see {Option +col_sep+}[#class-CSV-label-Option+col_sep]:
  #   CSV.new('').col_sep # => ","
  def col_sep
    parser.column_separator
  end

  # :call-seq:
  #   csv.row_sep -> string
  #
  # Returns the encoded row separator; used for parsing and writing;
  # see {Option +row_sep+}[#class-CSV-label-Option+row_sep]:
  #   CSV.new('').row_sep # => "\n"
  def row_sep
    parser.row_separator
  end

  # :call-seq:
  #   csv.quote_char -> character
  #
  # Returns the encoded quote character; used for parsing and writing;
  # see {Option +quote_char+}[#class-CSV-label-Option+quote_char]:
  #   CSV.new('').quote_char # => "\""
  def quote_char
    parser.quote_character
  end

  # :call-seq:
  #   csv.field_size_limit -> integer or nil
  #
  # Returns the limit for field size; used for parsing;
  # see {Option +field_size_limit+}[#class-CSV-label-Option+field_size_limit]:
  #   CSV.new('').field_size_limit # => nil
  #
  # Deprecated since 3.2.3. Use +max_field_size+ instead.
  def field_size_limit
    parser.field_size_limit
  end

  # :call-seq:
  #   csv.max_field_size -> integer or nil
  #
  # Returns the limit for field size; used for parsing;
  # see {Option +max_field_size+}[#class-CSV-label-Option+max_field_size]:
  #   CSV.new('').max_field_size # => nil
  #
  # Since 3.2.3.
  def max_field_size
    parser.max_field_size
  end

  # :call-seq:
  #   csv.skip_lines -> regexp or nil
  #
  # Returns the \Regexp used to identify comment lines; used for parsing;
  # see {Option +skip_lines+}[#class-CSV-label-Option+skip_lines]:
  #   CSV.new('').skip_lines # => nil
  def skip_lines
    parser.skip_lines
  end

  # :call-seq:
  #   csv.converters -> array
  #
  # Returns an \Array containing field converters;
  # see {Field Converters}[#class-CSV-label-Field+Converters]:
  #   csv = CSV.new('')
  #   csv.converters # => []
  #   csv.convert(:integer)
  #   csv.converters # => [:integer]
  #   csv.convert(proc {|x| x.to_s })
  #   csv.converters
  #
  # Notes that you need to call
  # +Ractor.make_shareable(CSV::Converters)+ on the main Ractor to use
  # this method.
  def converters
    parser_fields_converter.map do |converter|
      name = Converters.rassoc(converter)
      name ? name.first : converter
    end
  end

  # :call-seq:
  #   csv.unconverted_fields? -> object
  #
  # Returns the value that determines whether unconverted fields are to be
  # available; used for parsing;
  # see {Option +unconverted_fields+}[#class-CSV-label-Option+unconverted_fields]:
  #   CSV.new('').unconverted_fields? # => nil
  def unconverted_fields?
    parser.unconverted_fields?
  end

  # :call-seq:
  #   csv.headers -> object
  #
  # Returns the value that determines whether headers are used; used for parsing;
  # see {Option +headers+}[#class-CSV-label-Option+headers]:
  #   CSV.new('').headers # => nil
  def headers
    if @writer
      @writer.headers
    else
      parsed_headers = parser.headers
      return parsed_headers if parsed_headers
      raw_headers = @parser_options[:headers]
      raw_headers = nil if raw_headers == false
      raw_headers
    end
  end

  # :call-seq:
  #   csv.return_headers? -> true or false
  #
  # Returns the value that determines whether headers are to be returned; used for parsing;
  # see {Option +return_headers+}[#class-CSV-label-Option+return_headers]:
  #   CSV.new('').return_headers? # => false
  def return_headers?
    parser.return_headers?
  end

  # :call-seq:
  #   csv.write_headers? -> true or false
  #
  # Returns the value that determines whether headers are to be written; used for generating;
  # see {Option +write_headers+}[#class-CSV-label-Option+write_headers]:
  #   CSV.new('').write_headers? # => nil
  def write_headers?
    @writer_options[:write_headers]
  end

  # :call-seq:
  #   csv.header_converters -> array
  #
  # Returns an \Array containing header converters; used for parsing;
  # see {Header Converters}[#class-CSV-label-Header+Converters]:
  #   CSV.new('').header_converters # => []
  #
  # Notes that you need to call
  # +Ractor.make_shareable(CSV::HeaderConverters)+ on the main Ractor
  # to use this method.
  def header_converters
    header_fields_converter.map do |converter|
      name = HeaderConverters.rassoc(converter)
      name ? name.first : converter
    end
  end

  # :call-seq:
  #   csv.skip_blanks? -> true or false
  #
  # Returns the value that determines whether blank lines are to be ignored; used for parsing;
  # see {Option +skip_blanks+}[#class-CSV-label-Option+skip_blanks]:
  #   CSV.new('').skip_blanks? # => false
  def skip_blanks?
    parser.skip_blanks?
  end

  # :call-seq:
  #   csv.force_quotes? -> true or false
  #
  # Returns the value that determines whether all output fields are to be quoted;
  # used for generating;
  # see {Option +force_quotes+}[#class-CSV-label-Option+force_quotes]:
  #   CSV.new('').force_quotes? # => false
  def force_quotes?
    @writer_options[:force_quotes]
  end

  # :call-seq:
  #   csv.liberal_parsing? -> true or false
  #
  # Returns the value that determines whether illegal input is to be handled; used for parsing;
  # see {Option +liberal_parsing+}[#class-CSV-label-Option+liberal_parsing]:
  #   CSV.new('').liberal_parsing? # => false
  def liberal_parsing?
    parser.liberal_parsing?
  end

  # :call-seq:
  #   csv.encoding -> encoding
  #
  # Returns the encoding used for parsing and generating;
  # see {Character Encodings (M17n or Multilingualization)}[#class-CSV-label-Character+Encodings+-28M17n+or+Multilingualization-29]:
  #   CSV.new('').encoding # => #<Encoding:UTF-8>
  attr_reader :encoding

  # :call-seq:
  #   csv.line_no -> integer
  #
  # Returns the count of the rows parsed or generated.
  #
  # Parsing:
  #   string = "foo,0\nbar,1\nbaz,2\n"
  #   path = 't.csv'
  #   File.write(path, string)
  #   CSV.open(path) do |csv|
  #     csv.each do |row|
  #       p [csv.lineno, row]
  #     end
  #   end
  # Output:
  #   [1, ["foo", "0"]]
  #   [2, ["bar", "1"]]
  #   [3, ["baz", "2"]]
  #
  # Generating:
  #   CSV.generate do |csv|
  #     p csv.lineno; csv << ['foo', 0]
  #     p csv.lineno; csv << ['bar', 1]
  #     p csv.lineno; csv << ['baz', 2]
  #   end
  # Output:
  #   0
  #   1
  #   2
  def lineno
    if @writer
      @writer.lineno
    else
      parser.lineno
    end
  end

  # :call-seq:
  #   csv.line -> array
  #
  # Returns the line most recently read:
  #   string = "foo,0\nbar,1\nbaz,2\n"
  #   path = 't.csv'
  #   File.write(path, string)
  #   CSV.open(path) do |csv|
  #     csv.each do |row|
  #       p [csv.lineno, csv.line]
  #     end
  #   end
  # Output:
  #   [1, "foo,0\n"]
  #   [2, "bar,1\n"]
  #   [3, "baz,2\n"]
  def line
    parser.line
  end

  ### IO and StringIO Delegation ###

  extend Forwardable
  def_delegators :@io, :binmode, :close, :close_read, :close_write,
                       :closed?, :external_encoding, :fcntl,
                       :fileno, :flush, :fsync, :internal_encoding,
                       :isatty, :pid, :pos, :pos=, :reopen,
                       :seek, :string, :sync, :sync=, :tell,
                       :truncate, :tty?

  def binmode?
    if @io.respond_to?(:binmode?)
      @io.binmode?
    else
      false
    end
  end

  def flock(*args)
    raise NotImplementedError unless @io.respond_to?(:flock)
    @io.flock(*args)
  end

  def ioctl(*args)
    raise NotImplementedError unless @io.respond_to?(:ioctl)
    @io.ioctl(*args)
  end

  def path
    @io.path if @io.respond_to?(:path)
  end

  def stat(*args)
    raise NotImplementedError unless @io.respond_to?(:stat)
    @io.stat(*args)
  end

  def to_i
    raise NotImplementedError unless @io.respond_to?(:to_i)
    @io.to_i
  end

  def to_io
    @io.respond_to?(:to_io) ? @io.to_io : @io
  end

  def eof?
    return false if @eof_error
    begin
      parser_enumerator.peek
      false
    rescue MalformedCSVError => error
      @eof_error = error
      false
    rescue StopIteration
      true
    end
  end
  alias_method :eof, :eof?

  # Rewinds the underlying IO object and resets CSV's lineno() counter.
  def rewind
    @parser = nil
    @parser_enumerator = nil
    @eof_error = nil
    @writer.rewind if @writer
    @io.rewind
  end

  ### End Delegation ###

  # :call-seq:
  #   csv << row -> self
  #
  # Appends a row to +self+.
  #
  # - Argument +row+ must be an \Array object or a CSV::Row object.
  # - The output stream must be open for writing.
  #
  # ---
  #
  # Append Arrays:
  #   CSV.generate do |csv|
  #     csv << ['foo', 0]
  #     csv << ['bar', 1]
  #     csv << ['baz', 2]
  #   end # => "foo,0\nbar,1\nbaz,2\n"
  #
  # Append CSV::Rows:
  #   headers = []
  #   CSV.generate do |csv|
  #     csv << CSV::Row.new(headers, ['foo', 0])
  #     csv << CSV::Row.new(headers, ['bar', 1])
  #     csv << CSV::Row.new(headers, ['baz', 2])
  #   end # => "foo,0\nbar,1\nbaz,2\n"
  #
  # Headers in CSV::Row objects are not appended:
  #   headers = ['Name', 'Count']
  #   CSV.generate do |csv|
  #     csv << CSV::Row.new(headers, ['foo', 0])
  #     csv << CSV::Row.new(headers, ['bar', 1])
  #     csv << CSV::Row.new(headers, ['baz', 2])
  #   end # => "foo,0\nbar,1\nbaz,2\n"
  #
  # ---
  #
  # Raises an exception if +row+ is not an \Array or \CSV::Row:
  #   CSV.generate do |csv|
  #     # Raises NoMethodError (undefined method `collect' for :foo:Symbol)
  #     csv << :foo
  #   end
  #
  # Raises an exception if the output stream is not opened for writing:
  #   path = 't.csv'
  #   File.write(path, '')
  #   File.open(path) do |file|
  #     CSV.open(file) do |csv|
  #       # Raises IOError (not opened for writing)
  #       csv << ['foo', 0]
  #     end
  #   end
  def <<(row)
    writer << row
    self
  end
  alias_method :add_row, :<<
  alias_method :puts,    :<<

  # :call-seq:
  #   convert(converter_name) -> array_of_procs
  #   convert {|field, field_info| ... } -> array_of_procs
  #
  # - With no block, installs a field converter (a \Proc).
  # - With a block, defines and installs a custom field converter.
  # - Returns the \Array of installed field converters.
  #
  # - Argument +converter_name+, if given, should be the name
  #   of an existing field converter.
  #
  # See {Field Converters}[#class-CSV-label-Field+Converters].
  # ---
  #
  # With no block, installs a field converter:
  #   csv = CSV.new('')
  #   csv.convert(:integer)
  #   csv.convert(:float)
  #   csv.convert(:date)
  #   csv.converters # => [:integer, :float, :date]
  #
  # ---
  #
  # The block, if given, is called for each field:
  # - Argument +field+ is the field value.
  # - Argument +field_info+ is a CSV::FieldInfo object
  #   containing details about the field.
  #
  # The examples here assume the prior execution of:
  #   string = "foo,0\nbar,1\nbaz,2\n"
  #   path = 't.csv'
  #   File.write(path, string)
  #
  # Example giving a block:
  #   csv = CSV.open(path)
  #   csv.convert {|field, field_info| p [field, field_info]; field.upcase }
  #   csv.read # => [["FOO", "0"], ["BAR", "1"], ["BAZ", "2"]]
  #
  # Output:
  #   ["foo", #<struct CSV::FieldInfo index=0, line=1, header=nil>]
  #   ["0", #<struct CSV::FieldInfo index=1, line=1, header=nil>]
  #   ["bar", #<struct CSV::FieldInfo index=0, line=2, header=nil>]
  #   ["1", #<struct CSV::FieldInfo index=1, line=2, header=nil>]
  #   ["baz", #<struct CSV::FieldInfo index=0, line=3, header=nil>]
  #   ["2", #<struct CSV::FieldInfo index=1, line=3, header=nil>]
  #
  # The block need not return a \String object:
  #   csv = CSV.open(path)
  #   csv.convert {|field, field_info| field.to_sym }
  #   csv.read # => [[:foo, :"0"], [:bar, :"1"], [:baz, :"2"]]
  #
  # If +converter_name+ is given, the block is not called:
  #   csv = CSV.open(path)
  #   csv.convert(:integer) {|field, field_info| fail 'Cannot happen' }
  #   csv.read # => [["foo", 0], ["bar", 1], ["baz", 2]]
  #
  # ---
  #
  # Raises a parse-time exception if +converter_name+ is not the name of a built-in
  # field converter:
  #   csv = CSV.open(path)
  #   csv.convert(:nosuch) => [nil]
  #   # Raises NoMethodError (undefined method `arity' for nil:NilClass)
  #   csv.read
  def convert(name = nil, &converter)
    parser_fields_converter.add_converter(name, &converter)
  end

  # :call-seq:
  #   header_convert(converter_name) -> array_of_procs
  #   header_convert {|header, field_info| ... } -> array_of_procs
  #
  # - With no block, installs a header converter (a \Proc).
  # - With a block, defines and installs a custom header converter.
  # - Returns the \Array of installed header converters.
  #
  # - Argument +converter_name+, if given, should be the name
  #   of an existing header converter.
  #
  # See {Header Converters}[#class-CSV-label-Header+Converters].
  # ---
  #
  # With no block, installs a header converter:
  #   csv = CSV.new('')
  #   csv.header_convert(:symbol)
  #   csv.header_convert(:downcase)
  #   csv.header_converters # => [:symbol, :downcase]
  #
  # ---
  #
  # The block, if given, is called for each header:
  # - Argument +header+ is the header value.
  # - Argument +field_info+ is a CSV::FieldInfo object
  #   containing details about the header.
  #
  # The examples here assume the prior execution of:
  #   string = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
  #   path = 't.csv'
  #   File.write(path, string)
  #
  # Example giving a block:
  #   csv = CSV.open(path, headers: true)
  #   csv.header_convert {|header, field_info| p [header, field_info]; header.upcase }
  #   table = csv.read
  #   table # => #<CSV::Table mode:col_or_row row_count:4>
  #   table.headers # => ["NAME", "VALUE"]
  #
  # Output:
  #   ["Name", #<struct CSV::FieldInfo index=0, line=1, header=nil>]
  #   ["Value", #<struct CSV::FieldInfo index=1, line=1, header=nil>]

  # The block need not return a \String object:
  #   csv = CSV.open(path, headers: true)
  #   csv.header_convert {|header, field_info| header.to_sym }
  #   table = csv.read
  #   table.headers # => [:Name, :Value]
  #
  # If +converter_name+ is given, the block is not called:
  #   csv = CSV.open(path, headers: true)
  #   csv.header_convert(:downcase) {|header, field_info| fail 'Cannot happen' }
  #   table = csv.read
  #   table.headers # => ["name", "value"]
  # ---
  #
  # Raises a parse-time exception if +converter_name+ is not the name of a built-in
  # field converter:
  #   csv = CSV.open(path, headers: true)
  #   csv.header_convert(:nosuch)
  #   # Raises NoMethodError (undefined method `arity' for nil:NilClass)
  #   csv.read
  def header_convert(name = nil, &converter)
    header_fields_converter.add_converter(name, &converter)
  end

  include Enumerable

  # :call-seq:
  #   csv.each -> enumerator
  #   csv.each {|row| ...}
  #
  # Calls the block with each successive row.
  # The data source must be opened for reading.
  #
  # Without headers:
  #   string = "foo,0\nbar,1\nbaz,2\n"
  #   csv = CSV.new(string)
  #   csv.each do |row|
  #     p row
  #   end
  # Output:
  #   ["foo", "0"]
  #   ["bar", "1"]
  #   ["baz", "2"]
  #
  # With headers:
  #   string = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
  #   csv = CSV.new(string, headers: true)
  #   csv.each do |row|
  #     p row
  #   end
  # Output:
  #   <CSV::Row "Name":"foo" "Value":"0">
  #   <CSV::Row "Name":"bar" "Value":"1">
  #   <CSV::Row "Name":"baz" "Value":"2">
  #
  # ---
  #
  # Raises an exception if the source is not opened for reading:
  #   string = "foo,0\nbar,1\nbaz,2\n"
  #   csv = CSV.new(string)
  #   csv.close
  #   # Raises IOError (not opened for reading)
  #   csv.each do |row|
  #     p row
  #   end
  def each(&block)
    return to_enum(__method__) unless block_given?
    begin
      while true
        yield(parser_enumerator.next)
      end
    rescue StopIteration
    end
  end

  # :call-seq:
  #   csv.read -> array or csv_table
  #
  # Forms the remaining rows from +self+ into:
  # - A CSV::Table object, if headers are in use.
  # - An \Array of Arrays, otherwise.
  #
  # The data source must be opened for reading.
  #
  # Without headers:
  #   string = "foo,0\nbar,1\nbaz,2\n"
  #   path = 't.csv'
  #   File.write(path, string)
  #   csv = CSV.open(path)
  #   csv.read # => [["foo", "0"], ["bar", "1"], ["baz", "2"]]
  #
  # With headers:
  #   string = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
  #   path = 't.csv'
  #   File.write(path, string)
  #   csv = CSV.open(path, headers: true)
  #   csv.read # => #<CSV::Table mode:col_or_row row_count:4>
  #
  # ---
  #
  # Raises an exception if the source is not opened for reading:
  #   string = "foo,0\nbar,1\nbaz,2\n"
  #   csv = CSV.new(string)
  #   csv.close
  #   # Raises IOError (not opened for reading)
  #   csv.read
  def read
    rows = to_a
    if parser.use_headers?
      Table.new(rows, headers: parser.headers)
    else
      rows
    end
  end
  alias_method :readlines, :read

  # :call-seq:
  #   csv.header_row? -> true or false
  #
  # Returns +true+ if the next row to be read is a header row\;
  # +false+ otherwise.
  #
  # Without headers:
  #   string = "foo,0\nbar,1\nbaz,2\n"
  #   csv = CSV.new(string)
  #   csv.header_row? # => false
  #
  # With headers:
  #   string = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
  #   csv = CSV.new(string, headers: true)
  #   csv.header_row? # => true
  #   csv.shift # => #<CSV::Row "Name":"foo" "Value":"0">
  #   csv.header_row? # => false
  #
  # ---
  #
  # Raises an exception if the source is not opened for reading:
  #   string = "foo,0\nbar,1\nbaz,2\n"
  #   csv = CSV.new(string)
  #   csv.close
  #   # Raises IOError (not opened for reading)
  #   csv.header_row?
  def header_row?
    parser.header_row?
  end

  # :call-seq:
  #   csv.shift -> array, csv_row, or nil
  #
  # Returns the next row of data as:
  # - An \Array if no headers are used.
  # - A CSV::Row object if headers are used.
  #
  # The data source must be opened for reading.
  #
  # Without headers:
  #   string = "foo,0\nbar,1\nbaz,2\n"
  #   csv = CSV.new(string)
  #   csv.shift # => ["foo", "0"]
  #   csv.shift # => ["bar", "1"]
  #   csv.shift # => ["baz", "2"]
  #   csv.shift # => nil
  #
  # With headers:
  #   string = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
  #   csv = CSV.new(string, headers: true)
  #   csv.shift # => #<CSV::Row "Name":"foo" "Value":"0">
  #   csv.shift # => #<CSV::Row "Name":"bar" "Value":"1">
  #   csv.shift # => #<CSV::Row "Name":"baz" "Value":"2">
  #   csv.shift # => nil
  #
  # ---
  #
  # Raises an exception if the source is not opened for reading:
  #   string = "foo,0\nbar,1\nbaz,2\n"
  #   csv = CSV.new(string)
  #   csv.close
  #   # Raises IOError (not opened for reading)
  #   csv.shift
  def shift
    if @eof_error
      eof_error, @eof_error = @eof_error, nil
      raise eof_error
    end
    begin
      parser_enumerator.next
    rescue StopIteration
      nil
    end
  end
  alias_method :gets,     :shift
  alias_method :readline, :shift

  # :call-seq:
  #   csv.inspect -> string
  #
  # Returns a \String showing certain properties of +self+:
  #   string = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
  #   csv = CSV.new(string, headers: true)
  #   s = csv.inspect
  #   s # => "#<CSV io_type:StringIO encoding:UTF-8 lineno:0 col_sep:\",\" row_sep:\"\\n\" quote_char:\"\\\"\" headers:true>"
  def inspect
    str = ["#<", self.class.to_s, " io_type:"]
    # show type of wrapped IO
    if    @io == $stdout then str << "$stdout"
    elsif @io == $stdin  then str << "$stdin"
    elsif @io == $stderr then str << "$stderr"
    else                      str << @io.class.to_s
    end
    # show IO.path(), if available
    if @io.respond_to?(:path) and (p = @io.path)
      str << " io_path:" << p.inspect
    end
    # show encoding
    str << " encoding:" << @encoding.name
    # show other attributes
    ["lineno", "col_sep", "row_sep", "quote_char"].each do |attr_name|
      if a = __send__(attr_name)
        str << " " << attr_name << ":" << a.inspect
      end
    end
    ["skip_blanks", "liberal_parsing"].each do |attr_name|
      if a = __send__("#{attr_name}?")
        str << " " << attr_name << ":" << a.inspect
      end
    end
    _headers = headers
    str << " headers:" << _headers.inspect if _headers
    str << ">"
    begin
      str.join('')
    rescue  # any encoding error
      str.map do |s|
        e = Encoding::Converter.asciicompat_encoding(s.encoding)
        e ? s.encode(e) : s.force_encoding("ASCII-8BIT")
      end.join('')
    end
  end

  private

  def determine_encoding(encoding, internal_encoding)
    # honor the IO encoding if we can, otherwise default to ASCII-8BIT
    io_encoding = raw_encoding
    return io_encoding if io_encoding

    return Encoding.find(internal_encoding) if internal_encoding

    if encoding
      encoding, = encoding.split(":", 2) if encoding.is_a?(String)
      return Encoding.find(encoding)
    end

    Encoding.default_internal || Encoding.default_external
  end

  def normalize_converters(converters)
    converters ||= []
    unless converters.is_a?(Array)
      converters = [converters]
    end
    converters.collect do |converter|
      case converter
      when Proc # custom code block
        [nil, converter]
      else # by name
        [converter, nil]
      end
    end
  end

  #
  # Processes +fields+ with <tt>@converters</tt>, or <tt>@header_converters</tt>
  # if +headers+ is passed as +true+, returning the converted field set. Any
  # converter that changes the field into something other than a String halts
  # the pipeline of conversion for that field. This is primarily an efficiency
  # shortcut.
  #
  def convert_fields(fields, headers = false)
    if headers
      header_fields_converter.convert(fields, nil, 0)
    else
      parser_fields_converter.convert(fields, @headers, lineno)
    end
  end

  #
  # Returns the encoding of the internal IO object.
  #
  def raw_encoding
    if @io.respond_to? :internal_encoding
      @io.internal_encoding || @io.external_encoding
    elsif @io.respond_to? :encoding
      @io.encoding
    else
      nil
    end
  end

  def parser_fields_converter
    @parser_fields_converter ||= build_parser_fields_converter
  end

  def build_parser_fields_converter
    specific_options = {
      builtin_converters_name: :Converters,
    }
    options = @base_fields_converter_options.merge(specific_options)
    build_fields_converter(@initial_converters, options)
  end

  def header_fields_converter
    @header_fields_converter ||= build_header_fields_converter
  end

  def build_header_fields_converter
    specific_options = {
      builtin_converters_name: :HeaderConverters,
      accept_nil: true,
    }
    options = @base_fields_converter_options.merge(specific_options)
    build_fields_converter(@initial_header_converters, options)
  end

  def writer_fields_converter
    @writer_fields_converter ||= build_writer_fields_converter
  end

  def build_writer_fields_converter
    build_fields_converter(@initial_write_converters,
                           @write_fields_converter_options)
  end

  def build_fields_converter(initial_converters, options)
    fields_converter = FieldsConverter.new(options)
    normalize_converters(initial_converters).each do |name, converter|
      fields_converter.add_converter(name, &converter)
    end
    fields_converter
  end

  def parser
    @parser ||= Parser.new(@io, parser_options)
  end

  def parser_options
    @parser_options.merge(header_fields_converter: header_fields_converter,
                          fields_converter: parser_fields_converter)
  end

  def parser_enumerator
    @parser_enumerator ||= parser.parse
  end

  def writer
    @writer ||= Writer.new(@io, writer_options)
  end

  def writer_options
    @writer_options.merge(header_fields_converter: header_fields_converter,
                          fields_converter: writer_fields_converter)
  end
end

# Passes +args+ to CSV::instance.
#
#   CSV("CSV,data").read
#     #=> [["CSV", "data"]]
#
# If a block is given, the instance is passed the block and the return value
# becomes the return value of the block.
#
#   CSV("CSV,data") { |c|
#     c.read.any? { |a| a.include?("data") }
#   } #=> true
#
#   CSV("CSV,data") { |c|
#     c.read.any? { |a| a.include?("zombies") }
#   } #=> false
#
# CSV options may also be given.
#
#   io = StringIO.new
#   CSV(io, col_sep: ";") { |csv| csv << ["a", "b", "c"] }
#
# This API is not Ractor-safe.
#
def CSV(*args, **options, &block)
  CSV.instance(*args, **options, &block)
end

require_relative "csv/version"
require_relative "csv/core_ext/array"
require_relative "csv/core_ext/string"
