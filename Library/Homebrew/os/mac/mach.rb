# typed: strict
# frozen_string_literal: true

require "macho"

# {Pathname} extension for dealing with Mach-O files.
module MachOShim
  extend Forwardable
  extend T::Helpers

  requires_ancestor { Pathname }

  delegate [:dylib_id] => :macho

  sig { params(args: T.untyped).void }
  def initialize(*args)
    @macho = T.let(nil, T.nilable(T.any(MachO::MachOFile, MachO::FatFile)))
    @mach_data = T.let(nil, T.nilable(T::Array[T::Hash[Symbol, Symbol]]))

    super
  end

  sig { returns(T.any(MachO::MachOFile, MachO::FatFile)) }
  def macho
    @macho ||= MachO.open(to_s)
  end
  private :macho

  sig { returns(T::Array[T::Hash[Symbol, Symbol]]) }
  def mach_data
    @mach_data ||= begin
      machos = []
      mach_data = []

      case (macho = self.macho)
      when MachO::FatFile
        machos = macho.machos
      else
        machos << macho
      end

      machos.each do |m|
        arch = case m.cputype
        when :x86_64, :i386, :ppc64, :arm64, :arm then m.cputype
        when :ppc then :ppc7400
        else :dunno
        end

        type = case m.filetype
        when :dylib, :bundle then m.filetype
        when :execute then :executable
        else :dunno
        end

        mach_data << { arch:, type: }
      end

      mach_data
    rescue MachO::NotAMachOError
      # Silently ignore errors that indicate the file is not a Mach-O binary ...
      []
    rescue
      # ... but complain about other (parse) errors for further investigation.
      onoe "Failed to read Mach-O binary: #{self}"
      raise if Homebrew::EnvConfig.developer?

      []
    end
  end
  private :mach_data

  # TODO: See if the `#write!` call can be delayed until
  #       we know we're not making any changes to the rpaths.
  sig { params(rpath: String, strict: T::Boolean).void }
  def delete_rpath(rpath, strict: true)
    candidates = rpaths(resolve_variable_references: false).select do |r|
      resolve_variable_name(r) == resolve_variable_name(rpath)
    end

    # Delete the last instance to avoid changing the order in which rpaths are searched.
    rpath_to_delete = candidates.last

    macho.delete_rpath(rpath_to_delete, { last: true, strict: })
    macho.write!
  end

  sig { params(old: String, new: String, uniq: T::Boolean, last: T::Boolean, strict: T::Boolean).void }
  def change_rpath(old, new, uniq: false, last: false, strict: true)
    macho.change_rpath(old, new, { uniq:, last:, strict: })
    macho.write!
  end

  sig { params(id: String, strict: T::Boolean).void }
  def change_dylib_id(id, strict: true)
    macho.change_dylib_id(id, { strict: })
    macho.write!
  end

  sig { params(old: String, new: String, strict: T::Boolean).void }
  def change_install_name(old, new, strict: true)
    macho.change_install_name(old, new, { strict: })
    macho.write!
  end

  sig { params(except: Symbol, resolve_variable_references: T::Boolean).returns(T::Array[String]) }
  def dynamically_linked_libraries(except: :none, resolve_variable_references: true)
    lcs = macho.dylib_load_commands
    lcs.reject! { |lc| lc.flag?(except) } if except != :none
    names = lcs.map { |lc| lc.name.to_s }.uniq
    names.map! { resolve_variable_name(it) } if resolve_variable_references

    names
  end

  sig { params(resolve_variable_references: T::Boolean).returns(T::Array[String]) }
  def rpaths(resolve_variable_references: true)
    names = macho.rpaths
    # Don't recursively resolve rpaths to avoid infinite loops.
    names.map! { |name| resolve_variable_name(name, resolve_rpaths: false) } if resolve_variable_references

    names
  end

  sig { params(name: String, resolve_rpaths: T::Boolean).returns(String) }
  def resolve_variable_name(name, resolve_rpaths: true)
    if name.start_with? "@loader_path"
      Pathname(name.sub("@loader_path", dirname.to_s)).cleanpath.to_s
    elsif name.start_with?("@executable_path") && binary_executable?
      Pathname(name.sub("@executable_path", dirname.to_s)).cleanpath.to_s
    elsif resolve_rpaths && name.start_with?("@rpath") && (target = resolve_rpath(name)).present?
      target
    else
      name
    end
  end

  sig { params(name: String).returns(T.nilable(String)) }
  def resolve_rpath(name)
    target = T.let(nil, T.nilable(String))
    return unless rpaths(resolve_variable_references: true).find do |rpath|
      File.exist?(target = File.join(rpath, name.delete_prefix("@rpath")))
    end

    target
  end

  sig { returns(T::Array[Symbol]) }
  def archs
    mach_data.map { |m| m.fetch :arch }
  end

  sig { returns(Symbol) }
  def arch
    case archs.length
    when 0 then :dunno
    when 1 then archs.fetch(0)
    else :universal
    end
  end

  sig { returns(T::Boolean) }
  def universal?
    arch == :universal
  end

  sig { returns(T::Boolean) }
  def i386?
    arch == :i386
  end

  sig { returns(T::Boolean) }
  def x86_64?
    arch == :x86_64
  end

  sig { returns(T::Boolean) }
  def ppc7400?
    arch == :ppc7400
  end

  sig { returns(T::Boolean) }
  def ppc64?
    arch == :ppc64
  end

  sig { returns(T::Boolean) }
  def dylib?
    mach_data.any? { |m| m.fetch(:type) == :dylib }
  end

  sig { returns(T::Boolean) }
  def mach_o_executable?
    mach_data.any? { |m| m.fetch(:type) == :executable }
  end

  alias binary_executable? mach_o_executable?

  sig { returns(T::Boolean) }
  def mach_o_bundle?
    mach_data.any? { |m| m.fetch(:type) == :bundle }
  end
end
