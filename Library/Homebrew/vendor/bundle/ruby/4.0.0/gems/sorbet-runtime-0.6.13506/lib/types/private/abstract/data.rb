# frozen_string_literal: true
# typed: true

# We need to associate data with abstract modules. We could add instance methods to them that
# access ivars, but those methods will unnecessarily pollute the module namespace, and they'd
# have access to other private state and methods that they don't actually need. We also need to
# associate data with arbitrary classes/modules that implement abstract mixins, where we don't
# control the interface at all. So, we access data via these `get` and `set` methods.
#
# Using instance_variable_get/set here is gross, but the alternative is to use a hash keyed on
# `mod`, and we can't trust that arbitrary modules can be added to those, because there are lurky
# modules that override the `hash` method with something completely broken.
module T::Private::Abstract::Data
  def self.get(mod, key)
    mod.instance_variable_get("@opus_abstract__#{key}")
  end

  def self.set(mod, key, value)
    mod.instance_variable_set("@opus_abstract__#{key}", value)
  end

  def self.key?(mod, key)
    mod.instance_variable_defined?("@opus_abstract__#{key}")
  end

  # Works like `setdefault` in Python. If key has already been set, return its value. If not,
  # insert `key` with a value of `default` and return `default`.
  def self.set_default(mod, key, default)
    if self.key?(mod, key)
      self.get(mod, key)
    else
      self.set(mod, key, default)
      default
    end
  end
end
