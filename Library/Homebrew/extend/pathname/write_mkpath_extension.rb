# typed: strict
# frozen_string_literal: true

module WriteMkpathExtension
  extend T::Helpers

  requires_ancestor { Pathname }

  # Source for `sig`: https://github.com/sorbet/sorbet/blob/b4092efe0a4489c28aff7e1ead6ee8a0179dc8b3/rbi/stdlib/pathname.rbi#L1392-L1411
  sig {
    params(
      content:           Object,
      offset:            Integer,
      external_encoding: T.any(String, Encoding),
      internal_encoding: T.any(String, Encoding),
      encoding:          T.any(String, Encoding),
      textmode:          BasicObject,
      binmode:           BasicObject,
      autoclose:         BasicObject,
      mode:              String,
      perm:              Integer,
    ).returns(Integer)
  }
  def write(content, offset = T.unsafe(nil), external_encoding: T.unsafe(nil), internal_encoding: T.unsafe(nil),
            encoding: T.unsafe(nil), textmode: T.unsafe(nil), binmode: T.unsafe(nil), autoclose: T.unsafe(nil),
            mode: T.unsafe(nil), perm: T.unsafe(nil))
    raise "Will not overwrite #{self}" if exist? && !offset && !mode&.match?(/^a\+?$/)

    dirname.mkpath

    super
  end
end
