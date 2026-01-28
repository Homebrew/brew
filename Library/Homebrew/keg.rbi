# typed: strict

class Keg
  # This is only true under MacOS, so can lead to true negative type errors
  include OS::Mac::Keg
end
