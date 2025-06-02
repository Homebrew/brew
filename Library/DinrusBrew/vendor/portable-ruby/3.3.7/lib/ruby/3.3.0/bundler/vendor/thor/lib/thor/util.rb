require "rbconfig"

class Bundler::Thor
  module Sandbox #:nodoc:
  end

  # This module holds several utilities:
  #
  # 1) Methods to convert thor namespaces to constants and vice-versa.
  #
  #   Bundler::Thor::Util.namespace_from_thor_class(Foo::Bar::Baz) #=> "foo:bar:baz"
  #
  # 2) Loading thor files and sandboxing:
  #
  #   Bundler::Thor::Util.load_thorfile("~/.thor/foo")
  #
  module Util
    class << self
      # Receives a namespace and search for it in the Bundler::Thor::Base subclasses.
      #
      # ==== Parameters
      # namespace<String>:: The namespace to search for.
      #
      def find_by_namespace(namespace)
        namespace = "default#{namespace}" if namespace.empty? || namespace =~ /^:/
        Bundler::Thor::Base.subclasses.detect { |klass| klass.namespace == namespace }
      end

      # Receives a constant and converts it to a Bundler::Thor namespace. Since Bundler::Thor
      # commands can be added to a sandbox, this method is also responsible for
      # removing the sandbox namespace.
      #
      # This method should not be used in general because it's used to deal with
      # older versions of Bundler::Thor. On current versions, if you need to get the
      # namespace from a class, just call namespace on it.
      #
      # ==== Parameters
      # constant<Object>:: The constant to be converted to the thor path.
      #
      # ==== Returns
      # String:: If we receive Foo::Bar::Baz it returns "foo:bar:baz"
      #
      def namespace_from_thor_class(constant)
        constant = constant.to_s.gsub(/^Bundler::Thor::Sandbox::/, "")
        constant = snake_case(constant).squeeze(":")
        constant
      end

      # Given the contents, evaluate it inside the sandbox and returns the
      # namespaces defined in the sandbox.
      #
      # ==== Parameters
      # contents<String>
      #
      # ==== Returns
      # Array[Object]
      #
      def namespaces_in_content(contents, file = __FILE__)
        old_constants = Bundler::Thor::Base.subclasses.dup
        Bundler::Thor::Base.subclasses.clear

        load_thorfile(file, contents)

        new_constants = Bundler::Thor::Base.subclasses.dup
        Bundler::Thor::Base.subclasses.replace(old_constants)

        new_constants.map!(&:namespace)
        new_constants.compact!
        new_constants
      end

      # Returns the thor classes declared inside the given class.
      #
      def thor_classes_in(klass)
        stringfied_constants = klass.constants.map(&:to_s)
        Bundler::Thor::Base.subclasses.select do |subclass|
          next unless subclass.name
          stringfied_constants.include?(subclass.name.gsub("#{klass.name}::", ""))
        end
      end

      # Receives a string and convert it to snake case. SnakeCase returns snake_case.
      #
      # ==== Parameters
      # String
      #
      # ==== Returns
      # String
      #
      def snake_case(str)
        return str.downcase if str =~ /^[A-Z_]+$/
        str.gsub(/\B[A-Z]/, '_\&').squeeze("_") =~ /_*(.*)/
        Regexp.last_match(-1).downcase
      end

      # Receives a string and convert it to camel case. camel_case returns CamelCase.
      #
      # ==== Parameters
      # String
      #
      # ==== Returns
      # String
      #
      def camel_case(str)
        return str if str !~ /_/ && str =~ /[A-Z]+.*/
        str.split("_").map(&:capitalize).join
      end

      # Receives a namespace and tries to retrieve a Bundler::Thor or Bundler::Thor::Group class
      # from it. It first searches for a class using the all the given namespace,
      # if it's not found, removes the highest entry and searches for the class
      # again. If found, returns the highest entry as the class name.
      #
      # ==== Examples
      #
      #   class Foo::Bar < Bundler::Thor
      #     def baz
      #     end
      #   end
      #
      #   class Baz::Foo < Bundler::Thor::Group
      #   end
      #
      #   Bundler::Thor::Util.namespace_to_thor_class("foo:bar")     #=> Foo::Bar, nil # will invoke default command
      #   Bundler::Thor::Util.namespace_to_thor_class("baz:foo")     #=> Baz::Foo, nil
      #   Bundler::Thor::Util.namespace_to_thor_class("foo:bar:baz") #=> Foo::Bar, "baz"
      #
      # ==== Parameters
      # namespace<String>
      #
      def find_class_and_command_by_namespace(namespace, fallback = true)
        if namespace.include?(":") # look for a namespaced command
          *pieces, command  = namespace.split(":")
          namespace = pieces.join(":")
          namespace = "default" if namespace.empty?
          klass = Bundler::Thor::Base.subclasses.detect { |thor| thor.namespace == namespace && thor.commands.keys.include?(command) }
        end
        unless klass # look for a Bundler::Thor::Group with the right name
          klass = Bundler::Thor::Util.find_by_namespace(namespace)
          command = nil
        end
        if !klass && fallback # try a command in the default namespace
          command = namespace
          klass   = Bundler::Thor::Util.find_by_namespace("")
        end
        [klass, command]
      end
      alias_method :find_class_and_task_by_namespace, :find_class_and_command_by_namespace

      # Receives a path and load the thor file in the path. The file is evaluated
      # inside the sandbox to avoid namespacing conflicts.
      #
      def load_thorfile(path, content = nil, debug = false)
        content ||= File.read(path)

        begin
          Bundler::Thor::Sandbox.class_eval(content, path)
        rescue StandardError => e
          $stderr.puts("WARNING: unable to load thorfile #{path.inspect}: #{e.message}")
          if debug
            $stderr.puts(*e.backtrace)
          else
            $stderr.puts(e.backtrace.first)
          end
        end
      end

      def user_home
        @@user_home ||= if ENV["HOME"]
          ENV["HOME"]
        elsif ENV["USERPROFILE"]
          ENV["USERPROFILE"]
        elsif ENV["HOMEDRIVE"] && ENV["HOMEPATH"]
          File.join(ENV["HOMEDRIVE"], ENV["HOMEPATH"])
        elsif ENV["APPDATA"]
          ENV["APPDATA"]
        else
          begin
            File.expand_path("~")
          rescue
            if File::ALT_SEPARATOR
              "C:/"
            else
              "/"
            end
          end
        end
      end

      # Returns the root where thor files are located, depending on the OS.
      #
      def thor_root
        File.join(user_home, ".thor").tr("\\", "/")
      end

      # Returns the files in the thor root. On Windows thor_root will be something
      # like this:
      #
      #   C:\Documents and Settings\james\.thor
      #
      # If we don't #gsub the \ character, Dir.glob will fail.
      #
      def thor_root_glob
        files = Dir["#{escape_globs(thor_root)}/*"]

        files.map! do |file|
          File.directory?(file) ? File.join(file, "main.thor") : file
        end
      end

      # Where to look for Bundler::Thor files.
      #
      def globs_for(path)
        path = escape_globs(path)
        ["#{path}/Thorfile", "#{path}/*.thor", "#{path}/tasks/*.thor", "#{path}/lib/tasks/**/*.thor"]
      end

      # Return the path to the ruby interpreter taking into account multiple
      # installations and windows extensions.
      #
      def ruby_command
        @ruby_command ||= begin
          ruby_name = RbConfig::CONFIG["ruby_install_name"]
          ruby = File.join(RbConfig::CONFIG["bindir"], ruby_name)
          ruby << RbConfig::CONFIG["EXEEXT"]

          # avoid using different name than ruby (on platforms supporting links)
          if ruby_name != "ruby" && File.respond_to?(:readlink)
            begin
              alternate_ruby = File.join(RbConfig::CONFIG["bindir"], "ruby")
              alternate_ruby << RbConfig::CONFIG["EXEEXT"]

              # ruby is a symlink
              if File.symlink? alternate_ruby
                linked_ruby = File.readlink alternate_ruby

                # symlink points to 'ruby_install_name'
                ruby = alternate_ruby if linked_ruby == ruby_name || linked_ruby == ruby
              end
            rescue NotImplementedError # rubocop:disable Lint/HandleExceptions
              # just ignore on windows
            end
          end

          # escape string in case path to ruby executable contain spaces.
          ruby.sub!(/.*\s.*/m, '"\&"')
          ruby
        end
      end

      # Returns a string that has had any glob characters escaped.
      # The glob characters are `* ? { } [ ]`.
      #
      # ==== Examples
      #
      #   Bundler::Thor::Util.escape_globs('[apps]')   # => '\[apps\]'
      #
      # ==== Parameters
      # String
      #
      # ==== Returns
      # String
      #
      def escape_globs(path)
        path.to_s.gsub(/[*?{}\[\]]/, '\\\\\\&')
      end

      # Returns a string that has had any HTML characters escaped.
      #
      # ==== Examples
      #
      #   Bundler::Thor::Util.escape_html('<div>')   # => "&lt;div&gt;"
      #
      # ==== Parameters
      # String
      #
      # ==== Returns
      # String
      #
      def escape_html(string)
        CGI.escapeHTML(string)
      end
    end
  end
end
