# typed: strict
# frozen_string_literal: true

module WriteMkpathExtension
  extend T::Helpers

  requires_ancestor { Pathname }

  # Source for `sig`: https://github.com/sorbet/sorbet/blob/b4092efe0a4489c28aff7e1ead6ee8a0179dc8b3/rbi/stdlib/pathname.rbi#L1392-L1411
  sig {
    params(
      content:           Object,
      offset:            T.nilable(Integer),
      external_encoding: T.nilable(T.any(String, Encoding)),
      internal_encoding: T.nilable(T.any(String, Encoding)),
      encoding:          T.nilable(T.any(String, Encoding)),
      textmode:          BasicObject,
      binmode:           BasicObject,
      autoclose:         BasicObject,
      mode:              T.nilable(String),
      perm:              T.nilable(Integer),
    ).returns(Integer)
  }
  def write(content, offset = nil, external_encoding: nil, internal_encoding: nil, encoding: nil, textmode: nil,
            binmode: nil, autoclose: nil, mode: nil, perm: nil)
    raise "Will not overwrite #{self}" if exist? && !offset && !mode&.match?(/^a\+?$/)

    dirname.mkpath

    super
  end
end
