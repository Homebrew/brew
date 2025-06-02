# frozen_string_literal: true

module RBS
  class Writer
    attr_reader :out
    attr_reader :indentation

    def initialize(out:)
      @out = out
      @indentation = []
      @preserve = false
    end

    def preserve?
      @preserve
    end

    def preserve!(preserve: true)
      @preserve = preserve
      self
    end

    def indent(size = 2)
      indentation.push(" " * size)
      yield
    ensure
      indentation.pop
    end

    def prefix
      indentation.join()
    end

    def puts(string = "")
      if string.size > 0
        @out.puts("#{prefix}#{string}")
      else
        @out.puts
      end
    end

    def write_annotation(annotations)
      annotations.each do |annotation|
        string = annotation.string
        case
        when string !~ /\}/
          puts "%a{#{string}}"
        when string !~ /\)/
          puts "%a(#{string})"
        when string !~ /\]/
          puts "%a[#{string}]"
        when string !~ /\>/
          puts "%a<#{string}>"
        when string !~ /\|/
          puts "%a|#{string}|"
        end
      end
    end

    def write_comment(comment)
      if comment
        comment.string.lines.each do |line|
          line = line.chomp
          unless line.empty?
            puts "# #{line}"
          else
            puts "#"
          end
        end
      end
    end

    def write(decls)
      [nil, *decls].each_cons(2) do |prev, decl|
        raise unless decl

        preserve_empty_line(prev, decl)
        write_decl decl
      end
    end

    def write_decl(decl)
      case decl
      when AST::Declarations::Class
        super_class = if super_class = decl.super_class
                        " < #{name_and_args(super_class.name, super_class.args)}"
                      end
        write_comment decl.comment
        write_annotation decl.annotations
        puts "class #{name_and_params(decl.name, decl.type_params)}#{super_class}"

        indent do
          [nil, *decl.members].each_cons(2) do |prev, member|
            raise unless member

            preserve_empty_line prev, member
            write_member member
          end
        end

        puts "end"

      when AST::Declarations::Module
        self_type = unless decl.self_types.empty?
                      " : #{decl.self_types.join(", ")}"
                    end

        write_comment decl.comment
        write_annotation decl.annotations

        puts "module #{name_and_params(decl.name, decl.type_params)}#{self_type}"

        indent do
          decl.members.each.with_index do |member, index|
            if index > 0
              puts
            end
            write_member member
          end
        end

        puts "end"
      when AST::Declarations::Constant
        write_comment decl.comment
        puts "#{decl.name}: #{decl.type}"

      when AST::Declarations::Global
        write_comment decl.comment
        puts "#{decl.name}: #{decl.type}"

      when AST::Declarations::Alias
        write_comment decl.comment
        write_annotation decl.annotations
        write_loc_source(decl) {
          puts "type #{name_and_params(decl.name, decl.type_params)} = #{decl.type}"
        }

      when AST::Declarations::Interface
        write_comment decl.comment
        write_annotation decl.annotations

        puts "interface #{name_and_params(decl.name, decl.type_params)}"

        indent do
          decl.members.each.with_index do |member, index|
            if index > 0
              puts
            end
            write_member member
          end
        end

        puts "end"

      end
    end

    def name_and_params(name, params)
      if params.empty?
        "#{name}"
      else
        ps = params.each.map do |param|
          param.to_s
        end

        "#{name}[#{ps.join(", ")}]"
      end
    end

    def name_and_args(name, args)
      if name && args
        if args.empty?
          "#{name}"
        else
          "#{name}[#{args.join(", ")}]"
        end
      end
    end

    def put_lines(lines, leading_spaces:)
      lines.each_line.with_index do |line, index|
        line.chomp!
        line.rstrip!
        line.sub!(/\A( {,#{leading_spaces}})/, '') if index > 0

        puts line
      end
    end

    def write_member(member)
      case member
      when AST::Members::Include
        write_comment member.comment
        write_annotation member.annotations
        puts "include #{name_and_args(member.name, member.args)}"
      when AST::Members::Extend
        write_comment member.comment
        write_annotation member.annotations
        puts "extend #{name_and_args(member.name, member.args)}"
      when AST::Members::Prepend
        write_comment member.comment
        write_annotation member.annotations
        puts "prepend #{name_and_args(member.name, member.args)}"
      when AST::Members::AttrAccessor
        write_comment member.comment
        write_annotation member.annotations
        puts "#{attribute(:accessor, member)}"
      when AST::Members::AttrReader
        write_comment member.comment
        write_annotation member.annotations
        puts "#{attribute(:reader, member)}"
      when AST::Members::AttrWriter
        write_comment member.comment
        write_annotation member.annotations
        puts "#{attribute(:writer, member)}"
      when AST::Members::Public
        puts "public"
      when AST::Members::Private
        puts "private"
      when AST::Members::Alias
        write_comment member.comment
        write_annotation member.annotations
        new_name = member.singleton? ? "self.#{member.new_name}" : member.new_name
        old_name = member.singleton? ? "self.#{member.old_name}" : member.old_name
        puts "alias #{new_name} #{old_name}"
      when AST::Members::InstanceVariable
        write_comment member.comment
        puts "#{member.name}: #{member.type}"
      when AST::Members::ClassInstanceVariable
        write_comment member.comment
        puts "self.#{member.name}: #{member.type}"
      when AST::Members::ClassVariable
        write_comment member.comment
        puts "#{member.name}: #{member.type}"
      when AST::Members::MethodDefinition
        write_comment member.comment
        write_annotation member.annotations
        write_loc_source(member) { write_def member }
      else
        write_decl member
      end
    end

    def method_name(name)
      s = name.to_s

      case s
      when /\A(_?)[A-Za-z_]\w*(\?|!|=)?\Z/
        s
      when *%w(|  ^  &  <=>  ==  ===  =~  >   >=  <   <=   <<  >> +  -  *  /  %   **   ~   +@  -@  []  []=  ` ! != !~)
        s
      else
        "`#{s}`"
      end
    end

    def write_loc_source(located)
      if preserve? && loc = located.location
        put_lines(loc.source, leading_spaces: loc.start_column)
      else
        yield
      end
    end

    def write_def(member)
      visibility =
        case member.visibility
        when :public
          "public "
        when :private
          "private "
        else
          ""
        end

      name = case member.kind
             when :instance
               "#{method_name(member.name)}"
             when :singleton_instance
               "self?.#{method_name(member.name)}"
             when :singleton
               "self.#{method_name(member.name)}"
             end

      string = +""

      prefix = "#{visibility}def #{name}:"
      padding = " " * (prefix.size-1)

      string << prefix

      member.types.each.with_index do |type, index|
        if index > 0
          string << padding
          string << "|"
        end

        string << " #{type}\n"
      end

      if member.overload
        if member.types.size > 0
          string << padding
          string << "|"
        end
        string << " ...\n"
      end

      string.each_line do |line|
        puts line.chomp
      end
    end

    def attribute(kind, attr)
      visibility =
        case attr.visibility
        when :public
          "public "
        when :private
          "private "
        else
          ""
        end

      var = case attr.ivar_name
            when nil
              ""
            when false
              "()"
            else
              "(#{attr.ivar_name})"
            end

      receiver = case attr.kind
                 when :singleton
                   "self."
                 when :instance
                   ""
                 end

      "#{visibility}attr_#{kind} #{receiver}#{attr.name}#{var}: #{attr.type}"
    end

    def preserve_empty_line(prev, decl)
      # @type var decl: _Located

      return unless prev

      if (_ = decl).respond_to?(:comment)
        if comment = (_ = decl).comment
          decl = comment
        end
      end

      prev_loc = prev.location
      decl_loc = decl.location

      if prev_loc && decl_loc
        prev_end_line = prev_loc.end_line
        start_line = decl_loc.start_line

        if start_line - prev_end_line > 1
          puts
        end
      else
        # When the signature is not constructed by the parser,
        # it always inserts an empty line.
        puts
      end
    end
  end
end
