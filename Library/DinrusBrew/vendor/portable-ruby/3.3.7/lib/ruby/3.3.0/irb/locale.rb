# frozen_string_literal: true
#
#   irb/locale.rb - internationalization module
#   	by Keiju ISHITSUKA(keiju@ruby-lang.org)
#

module IRB # :nodoc:
  class Locale

    LOCALE_NAME_RE = %r[
      (?<language>[[:alpha:]]{2,3})
      (?:_  (?<territory>[[:alpha:]]{2,3}) )?
      (?:\. (?<codeset>[^@]+) )?
      (?:@  (?<modifier>.*) )?
    ]x
    LOCALE_DIR = "/lc/"

    LEGACY_ENCODING_ALIAS_MAP = {
      'ujis' => Encoding::EUC_JP,
      'euc' => Encoding::EUC_JP
    }

    @@loaded = []

    def initialize(locale = nil)
      @override_encoding = nil
      @lang = @territory = @encoding_name = @modifier = nil
      @locale = locale || ENV["IRB_LANG"] || ENV["LC_MESSAGES"] || ENV["LC_ALL"] || ENV["LANG"] || "C"
      if m = LOCALE_NAME_RE.match(@locale)
        @lang, @territory, @encoding_name, @modifier = m[:language], m[:territory], m[:codeset], m[:modifier]

        if @encoding_name
          if @encoding = LEGACY_ENCODING_ALIAS_MAP[@encoding_name]
            warn(("%s is obsolete. use %s" % ["#{@lang}_#{@territory}.#{@encoding_name}", "#{@lang}_#{@territory}.#{@encoding.name}"]), uplevel: 1)
          else
            @encoding = Encoding.find(@encoding_name) rescue nil
          end
        end
      end
      @encoding ||= (Encoding.find('locale') rescue Encoding::ASCII_8BIT)
    end

    attr_reader :lang, :territory, :modifier

    def encoding
      @override_encoding || @encoding
    end

    def String(mes)
      mes = super(mes)
      if encoding
        mes.encode(encoding, undef: :replace)
      else
        mes
      end
    end

    def format(*opts)
      String(super(*opts))
    end

    def gets(*rs)
      String(super(*rs))
    end

    def readline(*rs)
      String(super(*rs))
    end

    def print(*opts)
      ary = opts.collect{|opt| String(opt)}
      super(*ary)
    end

    def printf(*opts)
      s = format(*opts)
      print s
    end

    def puts(*opts)
      ary = opts.collect{|opt| String(opt)}
      super(*ary)
    end

    def load(file)
      found = find(file)
      if found
        unless @@loaded.include?(found)
          @@loaded << found # cache
          Kernel.load(found)
        end
      else
        raise LoadError, "No such file to load -- #{file}"
      end
    end

    def find(file, paths = $:)
      dir = File.dirname(file)
      dir = "" if dir == "."
      base = File.basename(file)

      if dir.start_with?('/')
        return each_localized_path(dir, base).find{|full_path| File.readable? full_path}
      else
        return search_file(paths, dir, base)
      end
    end

    # @param paths load paths in which IRB find a localized file.
    # @param dir directory
    # @param file basename to be localized
    #
    # typically, for the parameters and a <path> in paths, it searches
    #   <path>/<dir>/<locale>/<file>
    def search_file(lib_paths, dir, file)
      each_localized_path(dir, file) do |lc_path|
        lib_paths.each do |libpath|
          full_path = File.join(libpath, lc_path)
          return full_path if File.readable?(full_path)
        end
        redo if defined?(Gem) and Gem.try_activate(lc_path)
      end
      nil
    end

    def each_localized_path(dir, file)
      return enum_for(:each_localized_path) unless block_given?
      each_sublocale do |lc|
        yield lc.nil? ? File.join(dir, LOCALE_DIR, file) : File.join(dir, LOCALE_DIR, lc, file)
      end
    end

    def each_sublocale
      if @lang
        if @territory
          if @encoding_name
            yield "#{@lang}_#{@territory}.#{@encoding_name}@#{@modifier}" if @modifier
            yield "#{@lang}_#{@territory}.#{@encoding_name}"
          end
          yield "#{@lang}_#{@territory}@#{@modifier}" if @modifier
          yield "#{@lang}_#{@territory}"
        end
        if @encoding_name
          yield "#{@lang}.#{@encoding_name}@#{@modifier}" if @modifier
          yield "#{@lang}.#{@encoding_name}"
        end
        yield "#{@lang}@#{@modifier}" if @modifier
        yield "#{@lang}"
      end
      yield nil
    end
  end
end
