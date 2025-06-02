# frozen_string_literal: true

require "forwardable"

class CSV
  # = \CSV::Row
  # A \CSV::Row instance represents a \CSV table row.
  # (see {class CSV}[../CSV.html]).
  #
  # The instance may have:
  # - Fields: each is an object, not necessarily a \String.
  # - Headers: each serves a key, and also need not be a \String.
  #
  # === Instance Methods
  #
  # \CSV::Row has three groups of instance methods:
  # - Its own internally defined instance methods.
  # - Methods included by module Enumerable.
  # - Methods delegated to class Array.:
  #   * Array#empty?
  #   * Array#length
  #   * Array#size
  #
  # == Creating a \CSV::Row Instance
  #
  # Commonly, a new \CSV::Row instance is created by parsing \CSV source
  # that has headers:
  #   source = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
  #   table = CSV.parse(source, headers: true)
  #   table.each {|row| p row }
  # Output:
  #   #<CSV::Row "Name":"foo" "Value":"0">
  #   #<CSV::Row "Name":"bar" "Value":"1">
  #   #<CSV::Row "Name":"baz" "Value":"2">
  #
  # You can also create a row directly. See ::new.
  #
  # == Headers
  #
  # Like a \CSV::Table, a \CSV::Row has headers.
  #
  # A \CSV::Row that was created by parsing \CSV source
  # inherits its headers from the table:
  #   source = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
  #   table = CSV.parse(source, headers: true)
  #   row = table.first
  #   row.headers # => ["Name", "Value"]
  #
  # You can also create a new row with headers;
  # like the keys in a \Hash, the headers need not be Strings:
  #   row = CSV::Row.new([:name, :value], ['foo', 0])
  #   row.headers # => [:name, :value]
  #
  # The new row retains its headers even if added to a table
  # that has headers:
  #   table << row # => #<CSV::Table mode:col_or_row row_count:5>
  #   row.headers # => [:name, :value]
  #   row[:name] # => "foo"
  #   row['Name'] # => nil
  #
  #
  #
  # == Accessing Fields
  #
  # You may access a field in a \CSV::Row with either its \Integer index
  # (\Array-style) or its header (\Hash-style).
  #
  # Fetch a field using method #[]:
  #   row = CSV::Row.new(['Name', 'Value'], ['foo', 0])
  #   row[1] # => 0
  #   row['Value'] # => 0
  #
  # Set a field using method #[]=:
  #   row = CSV::Row.new(['Name', 'Value'], ['foo', 0])
  #   row # => #<CSV::Row "Name":"foo" "Value":0>
  #   row[0] = 'bar'
  #   row['Value'] = 1
  #   row # => #<CSV::Row "Name":"bar" "Value":1>
  #
  class Row
    # :call-seq:
    #   CSV::Row.new(headers, fields, header_row = false) -> csv_row
    #
    # Returns the new \CSV::Row instance constructed from
    # arguments +headers+ and +fields+; both should be Arrays;
    # note that the fields need not be Strings:
    #   row = CSV::Row.new(['Name', 'Value'], ['foo', 0])
    #   row # => #<CSV::Row "Name":"foo" "Value":0>
    #
    # If the \Array lengths are different, the shorter is +nil+-filled:
    #   row = CSV::Row.new(['Name', 'Value', 'Date', 'Size'], ['foo', 0])
    #   row # => #<CSV::Row "Name":"foo" "Value":0 "Date":nil "Size":nil>
    #
    # Each \CSV::Row object is either a <i>field row</i> or a <i>header row</i>;
    # by default, a new row is a field row;  for the row created above:
    #   row.field_row? # => true
    #   row.header_row? # => false
    #
    # If the optional argument +header_row+ is given as +true+,
    # the created row is a header row:
    #   row = CSV::Row.new(['Name', 'Value'], ['foo', 0], header_row = true)
    #   row # => #<CSV::Row "Name":"foo" "Value":0>
    #   row.field_row? # => false
    #   row.header_row? # => true
    def initialize(headers, fields, header_row = false)
      @header_row = header_row
      headers.each { |h| h.freeze if h.is_a? String }

      # handle extra headers or fields
      @row = if headers.size >= fields.size
        headers.zip(fields)
      else
        fields.zip(headers).each(&:reverse!)
      end
    end

    # Internal data format used to compare equality.
    attr_reader :row
    protected   :row

    ### Array Delegation ###

    extend Forwardable
    def_delegators :@row, :empty?, :length, :size

    # :call-seq:
    #   row.initialize_copy(other_row) -> self
    #
    # Calls superclass method.
    def initialize_copy(other)
      super_return_value = super
      @row = @row.collect(&:dup)
      super_return_value
    end

    # :call-seq:
    #   row.header_row? -> true or false
    #
    # Returns +true+ if this is a header row, +false+ otherwise.
    def header_row?
      @header_row
    end

    # :call-seq:
    #   row.field_row? -> true or false
    #
    # Returns +true+ if this is a field row, +false+ otherwise.
    def field_row?
      not header_row?
    end

    # :call-seq:
    #    row.headers -> array_of_headers
    #
    # Returns the headers for this row:
    #   source = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table.first
    #   row.headers # => ["Name", "Value"]
    def headers
      @row.map(&:first)
    end

    # :call-seq:
    #   field(index) -> value
    #   field(header) -> value
    #   field(header, offset) -> value
    #
    # Returns the field value for the given +index+ or +header+.
    #
    # ---
    #
    # Fetch field value by \Integer index:
    #   source = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   row.field(0) # => "foo"
    #   row.field(1) # => "bar"
    #
    # Counts backward from the last column if +index+ is negative:
    #   row.field(-1) # => "0"
    #   row.field(-2) # => "foo"
    #
    # Returns +nil+ if +index+ is out of range:
    #   row.field(2) # => nil
    #   row.field(-3) # => nil
    #
    # ---
    #
    # Fetch field value by header (first found):
    #   source = "Name,Name,Name\nFoo,Bar,Baz\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   row.field('Name') # => "Foo"
    #
    # Fetch field value by header, ignoring +offset+ leading fields:
    #   source = "Name,Name,Name\nFoo,Bar,Baz\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   row.field('Name', 2) # => "Baz"
    #
    # Returns +nil+ if the header does not exist.
    def field(header_or_index, minimum_index = 0)
      # locate the pair
      finder = (header_or_index.is_a?(Integer) || header_or_index.is_a?(Range)) ? :[] : :assoc
      pair   = @row[minimum_index..-1].public_send(finder, header_or_index)

      # return the field if we have a pair
      if pair.nil?
        nil
      else
        header_or_index.is_a?(Range) ? pair.map(&:last) : pair.last
      end
    end
    alias_method :[], :field

    #
    # :call-seq:
    #   fetch(header) -> value
    #   fetch(header, default) -> value
    #   fetch(header) {|row| ... } -> value
    #
    # Returns the field value as specified by +header+.
    #
    # ---
    #
    # With the single argument +header+, returns the field value
    # for that header (first found):
    #   source = "Name,Name,Name\nFoo,Bar,Baz\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   row.fetch('Name') # => "Foo"
    #
    # Raises exception +KeyError+ if the header does not exist.
    #
    # ---
    #
    # With arguments +header+ and +default+ given,
    # returns the field value for the header (first found)
    # if the header exists, otherwise returns +default+:
    #   source = "Name,Name,Name\nFoo,Bar,Baz\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   row.fetch('Name', '') # => "Foo"
    #   row.fetch(:nosuch, '') # => ""
    #
    # ---
    #
    # With argument +header+ and a block given,
    # returns the field value for the header (first found)
    # if the header exists; otherwise calls the block
    # and returns its return value:
    #   source = "Name,Name,Name\nFoo,Bar,Baz\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   row.fetch('Name') {|header| fail 'Cannot happen' } # => "Foo"
    #   row.fetch(:nosuch) {|header| "Header '#{header} not found'" } # => "Header 'nosuch not found'"
    def fetch(header, *varargs)
      raise ArgumentError, "Too many arguments" if varargs.length > 1
      pair = @row.assoc(header)
      if pair
        pair.last
      else
        if block_given?
          yield header
        elsif varargs.empty?
          raise KeyError, "key not found: #{header}"
        else
          varargs.first
        end
      end
    end

    # :call-seq:
    #   row.has_key?(header) -> true or false
    #
    # Returns +true+ if there is a field with the given +header+,
    # +false+ otherwise.
    def has_key?(header)
      !!@row.assoc(header)
    end
    alias_method :include?, :has_key?
    alias_method :key?,     :has_key?
    alias_method :member?,  :has_key?
    alias_method :header?,  :has_key?

    #
    # :call-seq:
    #   row[index] = value -> value
    #   row[header, offset] = value -> value
    #   row[header] = value -> value
    #
    # Assigns the field value for the given +index+ or +header+;
    # returns +value+.
    #
    # ---
    #
    # Assign field value by \Integer index:
    #   source = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   row[0] = 'Bat'
    #   row[1] = 3
    #   row # => #<CSV::Row "Name":"Bat" "Value":3>
    #
    # Counts backward from the last column if +index+ is negative:
    #   row[-1] = 4
    #   row[-2] = 'Bam'
    #   row # => #<CSV::Row "Name":"Bam" "Value":4>
    #
    # Extends the row with <tt>nil:nil</tt> if positive +index+ is not in the row:
    #   row[4] = 5
    #   row # => #<CSV::Row "Name":"bad" "Value":4 nil:nil nil:nil nil:5>
    #
    # Raises IndexError if negative +index+ is too small (too far from zero).
    #
    # ---
    #
    # Assign field value by header (first found):
    #   source = "Name,Name,Name\nFoo,Bar,Baz\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   row['Name'] = 'Bat'
    #   row # => #<CSV::Row "Name":"Bat" "Name":"Bar" "Name":"Baz">
    #
    # Assign field value by header, ignoring +offset+ leading fields:
    #   source = "Name,Name,Name\nFoo,Bar,Baz\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   row['Name', 2] = 4
    #   row # => #<CSV::Row "Name":"Foo" "Name":"Bar" "Name":4>
    #
    # Append new field by (new) header:
    #   source = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   row['New'] = 6
    #   row# => #<CSV::Row "Name":"foo" "Value":"0" "New":6>
    def []=(*args)
      value = args.pop

      if args.first.is_a? Integer
        if @row[args.first].nil?  # extending past the end with index
          @row[args.first] = [nil, value]
          @row.map! { |pair| pair.nil? ? [nil, nil] : pair }
        else                      # normal index assignment
          @row[args.first][1] = value
        end
      else
        index = index(*args)
        if index.nil?             # appending a field
          self << [args.first, value]
        else                      # normal header assignment
          @row[index][1] = value
        end
      end
    end

    #
    # :call-seq:
    #   row << [header, value] -> self
    #   row << hash -> self
    #   row << value -> self
    #
    # Adds a field to +self+; returns +self+:
    #
    # If the argument is a 2-element \Array <tt>[header, value]</tt>,
    # a field is added with the given +header+ and +value+:
    #   source = "Name,Name,Name\nFoo,Bar,Baz\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   row << ['NAME', 'Bat']
    #   row # => #<CSV::Row "Name":"Foo" "Name":"Bar" "Name":"Baz" "NAME":"Bat">
    #
    # If the argument is a \Hash, each <tt>key-value</tt> pair is added
    # as a field with header +key+ and value +value+.
    #   source = "Name,Name,Name\nFoo,Bar,Baz\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   row << {NAME: 'Bat', name: 'Bam'}
    #   row # => #<CSV::Row "Name":"Foo" "Name":"Bar" "Name":"Baz" NAME:"Bat" name:"Bam">
    #
    # Otherwise, the given +value+ is added as a field with no header.
    #   source = "Name,Name,Name\nFoo,Bar,Baz\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   row << 'Bag'
    #   row # => #<CSV::Row "Name":"Foo" "Name":"Bar" "Name":"Baz" nil:"Bag">
    def <<(arg)
      if arg.is_a?(Array) and arg.size == 2  # appending a header and name
        @row << arg
      elsif arg.is_a?(Hash)                  # append header and name pairs
        arg.each { |pair| @row << pair }
      else                                   # append field value
        @row << [nil, arg]
      end

      self  # for chaining
    end

    # :call-seq:
    #   row.push(*values) -> self
    #
    # Appends each of the given +values+ to +self+ as a field; returns +self+:
    #   source = "Name,Name,Name\nFoo,Bar,Baz\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   row.push('Bat', 'Bam')
    #   row # => #<CSV::Row "Name":"Foo" "Name":"Bar" "Name":"Baz" nil:"Bat" nil:"Bam">
    def push(*args)
      args.each { |arg| self << arg }

      self  # for chaining
    end

    #
    # :call-seq:
    #   delete(index) -> [header, value] or nil
    #   delete(header) -> [header, value] or empty_array
    #   delete(header, offset) -> [header, value] or empty_array
    #
    # Removes a specified field from +self+; returns the 2-element \Array
    # <tt>[header, value]</tt> if the field exists.
    #
    # If an \Integer argument +index+ is given,
    # removes and returns the field at offset +index+,
    # or returns +nil+ if the field does not exist:
    #   source = "Name,Name,Name\nFoo,Bar,Baz\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   row.delete(1) # => ["Name", "Bar"]
    #   row.delete(50) # => nil
    #
    # Otherwise, if the single argument +header+ is given,
    # removes and returns the first-found field with the given header,
    # of returns a new empty \Array if the field does not exist:
    #   source = "Name,Name,Name\nFoo,Bar,Baz\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   row.delete('Name') # => ["Name", "Foo"]
    #   row.delete('NAME') # => []
    #
    # If argument +header+ and \Integer argument +offset+ are given,
    # removes and returns the first-found field with the given header
    # whose +index+ is at least as large as +offset+:
    #   source = "Name,Name,Name\nFoo,Bar,Baz\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   row.delete('Name', 1) # => ["Name", "Bar"]
    #   row.delete('NAME', 1) # => []
    def delete(header_or_index, minimum_index = 0)
      if header_or_index.is_a? Integer                 # by index
        @row.delete_at(header_or_index)
      elsif i = index(header_or_index, minimum_index)  # by header
        @row.delete_at(i)
      else
        [ ]
      end
    end

    # :call-seq:
    #   row.delete_if {|header, value| ... } -> self
    #
    # Removes fields from +self+ as selected by the block; returns +self+.
    #
    # Removes each field for which the block returns a truthy value:
    #   source = "Name,Name,Name\nFoo,Bar,Baz\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   row.delete_if {|header, value| value.start_with?('B') } # => true
    #   row # => #<CSV::Row "Name":"Foo">
    #   row.delete_if {|header, value| header.start_with?('B') } # => false
    #
    # If no block is given, returns a new Enumerator:
    #   row.delete_if # => #<Enumerator: #<CSV::Row "Name":"Foo">:delete_if>
    def delete_if(&block)
      return enum_for(__method__) { size } unless block_given?

      @row.delete_if(&block)

      self  # for chaining
    end

    # :call-seq:
    #   self.fields(*specifiers) -> array_of_fields
    #
    # Returns field values per the given +specifiers+, which may be any mixture of:
    # - \Integer index.
    # - \Range of \Integer indexes.
    # - 2-element \Array containing a header and offset.
    # - Header.
    # - \Range of headers.
    #
    # For +specifier+ in one of the first four cases above,
    # returns the result of <tt>self.field(specifier)</tt>;  see #field.
    #
    # Although there may be any number of +specifiers+,
    # the examples here will illustrate one at a time.
    #
    # When the specifier is an \Integer +index+,
    # returns <tt>self.field(index)</tt>L
    #   source = "Name,Name,Name\nFoo,Bar,Baz\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   row.fields(1) # => ["Bar"]
    #
    # When the specifier is a \Range of \Integers +range+,
    # returns <tt>self.field(range)</tt>:
    #   row.fields(1..2) # => ["Bar", "Baz"]
    #
    # When the specifier is a 2-element \Array +array+,
    # returns <tt>self.field(array)</tt>L
    #   row.fields('Name', 1) # => ["Foo", "Bar"]
    #
    # When the specifier is a header +header+,
    # returns <tt>self.field(header)</tt>L
    #   row.fields('Name') # => ["Foo"]
    #
    # When the specifier is a \Range of headers +range+,
    # forms a new \Range +new_range+ from the indexes of
    # <tt>range.start</tt> and <tt>range.end</tt>,
    # and returns <tt>self.field(new_range)</tt>:
    #   source = "Name,NAME,name\nFoo,Bar,Baz\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   row.fields('Name'..'NAME') # => ["Foo", "Bar"]
    #
    # Returns all fields if no argument given:
    #   row.fields # => ["Foo", "Bar", "Baz"]
    def fields(*headers_and_or_indices)
      if headers_and_or_indices.empty?  # return all fields--no arguments
        @row.map(&:last)
      else                              # or work like values_at()
        all = []
        headers_and_or_indices.each do |h_or_i|
          if h_or_i.is_a? Range
            index_begin = h_or_i.begin.is_a?(Integer) ? h_or_i.begin :
                                                        index(h_or_i.begin)
            index_end   = h_or_i.end.is_a?(Integer)   ? h_or_i.end :
                                                        index(h_or_i.end)
            new_range   = h_or_i.exclude_end? ? (index_begin...index_end) :
                                                (index_begin..index_end)
            all.concat(fields.values_at(new_range))
          else
            all << field(*Array(h_or_i))
          end
        end
        return all
      end
    end
    alias_method :values_at, :fields

    # :call-seq:
    #   index(header) -> index
    #   index(header, offset) -> index
    #
    # Returns the index for the given header, if it exists;
    # otherwise returns +nil+.
    #
    # With the single argument +header+, returns the index
    # of the first-found field with the given +header+:
    #   source = "Name,Name,Name\nFoo,Bar,Baz\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   row.index('Name') # => 0
    #   row.index('NAME') # => nil
    #
    # With arguments +header+ and +offset+,
    # returns the index of the first-found field with given +header+,
    # but ignoring the first +offset+ fields:
    #   row.index('Name', 1) # => 1
    #   row.index('Name', 3) # => nil
    def index(header, minimum_index = 0)
      # find the pair
      index = headers[minimum_index..-1].index(header)
      # return the index at the right offset, if we found one
      index.nil? ? nil : index + minimum_index
    end

    # :call-seq:
    #   row.field?(value) -> true or false
    #
    # Returns +true+ if +value+ is a field in this row, +false+ otherwise:
    #   source = "Name,Name,Name\nFoo,Bar,Baz\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   row.field?('Bar') # => true
    #   row.field?('BAR') # => false
    def field?(data)
      fields.include? data
    end

    include Enumerable

    # :call-seq:
    #   row.each {|header, value| ... } -> self
    #
    # Calls the block with each header-value pair; returns +self+:
    #   source = "Name,Name,Name\nFoo,Bar,Baz\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   row.each {|header, value| p [header, value] }
    # Output:
    #   ["Name", "Foo"]
    #   ["Name", "Bar"]
    #   ["Name", "Baz"]
    #
    # If no block is given, returns a new Enumerator:
    #   row.each # => #<Enumerator: #<CSV::Row "Name":"Foo" "Name":"Bar" "Name":"Baz">:each>
    def each(&block)
      return enum_for(__method__) { size } unless block_given?

      @row.each(&block)

      self  # for chaining
    end

    alias_method :each_pair, :each

    # :call-seq:
    #   row == other -> true or false
    #
    # Returns +true+ if +other+ is a /CSV::Row that has the same
    # fields (headers and values) in the same order as +self+;
    # otherwise returns +false+:
    #   source = "Name,Name,Name\nFoo,Bar,Baz\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   other_row = table[0]
    #   row == other_row # => true
    #   other_row = table[1]
    #   row == other_row # => false
    def ==(other)
      return @row == other.row if other.is_a? CSV::Row
      @row == other
    end

    # :call-seq:
    #   row.to_h -> hash
    #
    # Returns the new \Hash formed by adding each header-value pair in +self+
    # as a key-value pair in the \Hash.
    #   source = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   row.to_h # => {"Name"=>"foo", "Value"=>"0"}
    #
    # Header order is preserved, but repeated headers are ignored:
    #   source = "Name,Name,Name\nFoo,Bar,Baz\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   row.to_h # => {"Name"=>"Foo"}
    def to_h
      hash = {}
      each do |key, _value|
        hash[key] = self[key] unless hash.key?(key)
      end
      hash
    end
    alias_method :to_hash, :to_h

    # :call-seq:
    #   row.deconstruct_keys(keys) -> hash
    #
    # Returns the new \Hash suitable for pattern matching containing only the
    # keys specified as an argument.
    def deconstruct_keys(keys)
      if keys.nil?
        to_h
      else
        keys.to_h { |key| [key, self[key]] }
      end
    end

    alias_method :to_ary, :to_a

    # :call-seq:
    #   row.deconstruct -> array
    #
    # Returns the new \Array suitable for pattern matching containing the values
    # of the row.
    def deconstruct
      fields
    end

    # :call-seq:
    #   row.to_csv -> csv_string
    #
    # Returns the row as a \CSV String. Headers are not included:
    #   source = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   row.to_csv # => "foo,0\n"
    def to_csv(**options)
      fields.to_csv(**options)
    end
    alias_method :to_s, :to_csv

    # :call-seq:
    #   row.dig(index_or_header, *identifiers) -> object
    #
    # Finds and returns the object in nested object that is specified
    # by +index_or_header+ and +specifiers+.
    #
    # The nested objects may be instances of various classes.
    # See {Dig Methods}[https://docs.ruby-lang.org/en/master/dig_methods_rdoc.html].
    #
    # Examples:
    #   source = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   row.dig(1) # => "0"
    #   row.dig('Value') # => "0"
    #   row.dig(5) # => nil
    def dig(index_or_header, *indexes)
      value = field(index_or_header)
      if value.nil?
        nil
      elsif indexes.empty?
        value
      else
        unless value.respond_to?(:dig)
          raise TypeError, "#{value.class} does not have \#dig method"
        end
        value.dig(*indexes)
      end
    end

    # :call-seq:
    #   row.inspect -> string
    #
    # Returns an ASCII-compatible \String showing:
    # - Class \CSV::Row.
    # - Header-value pairs.
    # Example:
    #   source = "Name,Value\nfoo,0\nbar,1\nbaz,2\n"
    #   table = CSV.parse(source, headers: true)
    #   row = table[0]
    #   row.inspect # => "#<CSV::Row \"Name\":\"foo\" \"Value\":\"0\">"
    def inspect
      str = ["#<", self.class.to_s]
      each do |header, field|
        str << " " << (header.is_a?(Symbol) ? header.to_s : header.inspect) <<
               ":" << field.inspect
      end
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
  end
end
