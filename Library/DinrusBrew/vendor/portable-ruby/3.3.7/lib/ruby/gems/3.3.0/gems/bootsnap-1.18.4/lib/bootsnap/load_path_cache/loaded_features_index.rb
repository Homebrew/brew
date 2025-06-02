# frozen_string_literal: true

module Bootsnap
  module LoadPathCache
    # LoadedFeaturesIndex partially mirrors an internal structure in ruby that
    # we can't easily obtain an interface to.
    #
    # This works around an issue where, without bootsnap, *ruby* knows that it
    # has already required a file by its short name (e.g. require 'bundler') if
    # a new instance of bundler is added to the $LOAD_PATH which resolves to a
    # different absolute path. This class makes bootsnap smart enough to
    # realize that it has already loaded 'bundler', and not just
    # '/path/to/bundler'.
    #
    # If you disable LoadedFeaturesIndex, you can see the problem this solves by:
    #
    # 1. `require 'a'`
    # 2. Prepend a new $LOAD_PATH element containing an `a.rb`
    # 3. `require 'a'`
    #
    # Ruby returns false from step 3.
    # With bootsnap but with no LoadedFeaturesIndex, this loads two different
    #   `a.rb`s.
    # With bootsnap and with LoadedFeaturesIndex, this skips the second load,
    #   returning false like ruby.
    class LoadedFeaturesIndex
      def initialize
        @lfi = {}
        @mutex = Mutex.new

        # In theory the user could mutate $LOADED_FEATURES and invalidate our
        # cache. If this ever comes up in practice - or if you, the
        # enterprising reader, feels inclined to solve this problem - we could
        # parallel the work done with ChangeObserver on $LOAD_PATH to mirror
        # updates to our @lfi.
        $LOADED_FEATURES.each do |feat|
          hash = feat.hash
          $LOAD_PATH.each do |lpe|
            next unless feat.start_with?(lpe)

            # /a/b/lib/my/foo.rb
            #          ^^^^^^^^^
            short = feat[(lpe.length + 1)..]
            stripped = strip_extension_if_elidable(short)
            @lfi[short] = hash
            @lfi[stripped] = hash
          end
        end
      end

      # We've optimized for initialize and register to be fast, and purge to be tolerable.
      # If access patterns make this not-okay, we can lazy-invert the LFI on
      # first purge and work from there.
      def purge(feature)
        @mutex.synchronize do
          feat_hash = feature.hash
          @lfi.reject! { |_, hash| hash == feat_hash }
        end
      end

      def purge_multi(features)
        rejected_hashes = features.each_with_object({}) { |f, h| h[f.hash] = true }
        @mutex.synchronize do
          @lfi.reject! { |_, hash| rejected_hashes.key?(hash) }
        end
      end

      def key?(feature)
        @mutex.synchronize { @lfi.key?(feature) }
      end

      def cursor(short)
        unless Bootsnap.absolute_path?(short.to_s)
          $LOADED_FEATURES.size
        end
      end

      def identify(short, cursor)
        $LOADED_FEATURES[cursor..].detect do |feat|
          offset = 0
          while (offset = feat.index(short, offset))
            if feat.index(".", offset + 1) && !feat.index("/", offset + 2)
              break true
            else
              offset += 1
            end
          end
        end
      end

      # There is a relatively uncommon case where we could miss adding an
      # entry:
      #
      # If the user asked for e.g. `require 'bundler'`, and we went through the
      # `FALLBACK_SCAN` pathway in `kernel_require.rb` and therefore did not
      # pass `long` (the full expanded absolute path), then we did are not able
      # to confidently add the `bundler.rb` form to @lfi.
      #
      # We could either:
      #
      # 1. Just add `bundler.rb`, `bundler.so`, and so on, which is close but
      #    not quite right; or
      # 2. Inspect $LOADED_FEATURES upon return from yield to find the matching
      #    entry.
      def register(short, long)
        return if Bootsnap.absolute_path?(short)

        hash = long.hash

        # Do we have a filename with an elidable extension, e.g.,
        # 'bundler.rb', or 'libgit2.so'?
        altname = if extension_elidable?(short)
          # Strip the extension off, e.g. 'bundler.rb' -> 'bundler'.
          strip_extension_if_elidable(short)
        elsif long && (ext = File.extname(long.freeze))
          # We already know the extension of the actual file this
          # resolves to, so put that back on.
          short + ext
        end

        @mutex.synchronize do
          @lfi[short] = hash
          (@lfi[altname] = hash) if altname
        end
      end

      private

      STRIP_EXTENSION = /\.[^.]*?$/.freeze
      private_constant(:STRIP_EXTENSION)

      # Might Ruby automatically search for this extension if
      # someone tries to 'require' the file without it? E.g. Ruby
      # will implicitly try 'x.rb' if you ask for 'x'.
      #
      # This is complex and platform-dependent, and the Ruby docs are a little
      # handwavy about what will be tried when and in what order.
      # So optimistically pretend that all known elidable extensions
      # will be tried on all platforms, and that people are unlikely
      # to name files in a way that assumes otherwise.
      # (E.g. It's unlikely that someone will know that their code
      # will _never_ run on MacOS, and therefore think they can get away
      # with calling a Ruby file 'x.dylib.rb' and then requiring it as 'x.dylib'.)
      #
      # See <https://ruby-doc.org/core-2.6.4/Kernel.html#method-i-require>.
      def extension_elidable?(feature)
        feature.to_s.end_with?(".rb", ".so", ".o", ".dll", ".dylib")
      end

      def strip_extension_if_elidable(feature)
        if extension_elidable?(feature)
          feature.sub(STRIP_EXTENSION, "")
        else
          feature
        end
      end
    end
  end
end
