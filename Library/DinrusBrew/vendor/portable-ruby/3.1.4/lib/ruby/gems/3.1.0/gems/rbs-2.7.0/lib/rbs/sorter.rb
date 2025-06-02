# frozen_string_literal: true

module RBS
  class Sorter
    include RBS::AST

    attr_reader :path, :stdout

    def initialize(path, stdout: $stdout)
      @path = path
      @stdout = stdout
    end

    def run
      stdout.puts "Opening #{path}..."

      buffer = Buffer.new(name: path, content: path.read)
      sigs = Parser.parse_signature(buffer)

      sigs.each do |m|
        sort_decl! m
      end

      stdout.puts "Writing #{path}..."
      path.open('w') do |out|
        writer = RBS::Writer.new(out: out)
        writer.write sigs
      end
    end

    def group(member)
      case member
      when Declarations::Alias
        -3
      when Declarations::Constant
        -2
      when Declarations::Class, Declarations::Module
        -1
      when Members::Include
        0.0
      when Members::Prepend
        0.2
      when Members::Extend
        0.4
      when Members::ClassVariable
        1
      when Members::ClassInstanceVariable
        2
      when Members::InstanceVariable
        3
      when Members::AttrAccessor, Members::AttrWriter, Members::AttrReader
        if member.kind == :singleton
          5.0
        else
          6.0
        end
      when Members::MethodDefinition
        case member.kind
        when :singleton_instance
          4
        when :singleton
          if member.name == :new
            5.2
          elsif member.visibility == :public
            5.4
          else
            5.6
          end
        else
          if member.name == :initialize
            6.2
          elsif member.visibility == :public
            6.4
          else
            6.6
          end
        end
      when Members::Alias
        if member.singleton?
          5.4
        else
          6.4
        end
      else
        raise
      end
    end

    def key(member)
      case member
      when Members::Include, Members::Extend, Members::Prepend
        member.name.to_s
      when Members::ClassVariable, Members::ClassInstanceVariable, Members::InstanceVariable
        member.name.to_s
      when Members::AttrAccessor, Members::AttrWriter, Members::AttrReader
        member.name.to_s
      when Members::MethodDefinition
        member.name.to_s
      when Members::Alias
        member.new_name.to_s
      when Declarations::Constant
        member.name.to_s
      when Declarations::Alias
        member.name.to_s
      when Declarations::Class, Declarations::Module
        member.name.to_s
      else
        raise
      end
    end

    def sort_decl!(decl)
      case decl
      when Declarations::Class, Declarations::Module, Declarations::Interface
        decl.members.each { |m| sort_decl! m }

        current_visibility = :public
        decl.members.map! do |m|
          case m
          when Members::Public
            current_visibility = :public
            nil
          when Members::Private
            current_visibility = :private
            nil
          when Members::MethodDefinition, Members::AttrReader, Members::AttrWriter, Members::AttrAccessor
            m.update(visibility: m.visibility || current_visibility)
          else
            m
          end
        end
        decl.members.compact!

        decl.members.sort! do |m1, m2|
          group1 = group(m1)
          group2 = group(m2)

          if group1 == group2
            key(m1) <=> key(m2)
          else
            group1 <=> group2
          end
        end

        current_visibility = :public
        decl.members.map! do |m|
          case m
          when Members::MethodDefinition, Members::AttrReader, Members::AttrWriter, Members::AttrAccessor
            new = m.update(visibility: nil)
            cur = current_visibility
            current_visibility = m.visibility
            if cur != m.visibility
              [
                m.visibility == :public ? Members::Public.new(location: nil) : Members::Private.new(location: nil),
                new
              ]
            else
              new
            end
          else
            m
          end
        end
        decl.members.flatten!
      end
    end
  end
end
