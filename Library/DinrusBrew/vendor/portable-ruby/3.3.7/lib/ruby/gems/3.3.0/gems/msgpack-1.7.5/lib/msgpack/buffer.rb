module MessagePack
  class Buffer
    # see ext for other methods

    # The semantic of duping a buffer is just too weird.
    undef_method :dup
    undef_method :clone
  end
end
