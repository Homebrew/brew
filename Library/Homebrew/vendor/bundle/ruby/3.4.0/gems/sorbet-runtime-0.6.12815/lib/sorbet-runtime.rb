# frozen_string_literal: true
# typed: true

# This file is hand-crafted to encode the dependencies. They load the whole type
# system since there is such a high chance of it being used, using an autoloader
# wouldn't buy us any startup time saving.

# Namespaces without any implementation
module T; end
module T::Helpers; end
module T::Private; end
module T::Private::Abstract; end
module T::Private::Types; end

# Each section is a group that I believe need a fixed ordering. There is also
# an ordering between groups.

# These are pre-reqs for almost everything in here.
require_relative 'types/configuration'
require_relative 'types/_types'
require_relative 'types/private/decl_state'
require_relative 'types/private/caller_utils'
require_relative 'types/private/class_utils'
require_relative 'types/private/runtime_levels'
require_relative 'types/private/methods/_methods'
require_relative 'types/sig'
require_relative 'types/helpers'
require_relative 'types/private/final'
require_relative 'types/private/sealed'

# The types themselves. First base classes
require_relative 'types/types/base'
require_relative 'types/types/typed_enumerable'
# Everything else
require_relative 'types/types/class_of'
require_relative 'types/types/enum'
require_relative 'types/types/fixed_array'
require_relative 'types/types/fixed_hash'
require_relative 'types/types/intersection'
require_relative 'types/types/noreturn'
require_relative 'types/types/anything'
require_relative 'types/types/proc'
require_relative 'types/types/attached_class'
require_relative 'types/types/self_type'
require_relative 'types/types/simple'
require_relative 'types/types/t_enum'
require_relative 'types/types/type_parameter'
require_relative 'types/types/typed_enumerator'
require_relative 'types/types/typed_enumerator_chain'
require_relative 'types/types/typed_enumerator_lazy'
require_relative 'types/types/typed_hash'
require_relative 'types/types/typed_range'
require_relative 'types/types/typed_set'
require_relative 'types/types/union'
require_relative 'types/types/untyped'
require_relative 'types/private/types/not_typed'
require_relative 'types/private/types/void'
require_relative 'types/private/types/string_holder'
require_relative 'types/private/types/type_alias'
require_relative 'types/private/types/simple_pair_union'

require_relative 'types/types/type_variable'
require_relative 'types/types/type_member'
require_relative 'types/types/type_template'

# Call validation
require_relative 'types/private/methods/modes'
require_relative 'types/private/methods/call_validation'

# Signature validation
require_relative 'types/private/methods/signature_validation'
require_relative 'types/abstract_utils'
require_relative 'types/private/abstract/validate'

# Catch all. Sort of built by `cd extn; find types -type f | grep -v test | sort`
require_relative 'types/generic'
require_relative 'types/private/abstract/declare'
require_relative 'types/private/abstract/hooks'
require_relative 'types/private/casts'
require_relative 'types/private/methods/decl_builder'
require_relative 'types/private/methods/signature'
require_relative 'types/private/retry'
require_relative 'types/utils'
require_relative 'types/boolean'

# Depends on types/utils
require_relative 'types/types/typed_array'
require_relative 'types/types/typed_module'
require_relative 'types/types/typed_class'

# Props dependencies
require_relative 'types/private/abstract/data'
require_relative 'types/private/mixins/mixins'
require_relative 'types/props/_props'
require_relative 'types/props/custom_type'
require_relative 'types/props/decorator'
require_relative 'types/props/errors'
require_relative 'types/props/plugin'
require_relative 'types/props/utils'
require_relative 'types/enum'
# Props that run sigs statically so have to be after all the others :(
require_relative 'types/props/private/setter_factory'
require_relative 'types/props/private/apply_default'
require_relative 'types/props/has_lazily_specialized_methods'
require_relative 'types/props/optional'
require_relative 'types/props/weak_constructor'
require_relative 'types/props/constructor'
require_relative 'types/props/pretty_printable'
require_relative 'types/props/private/serde_transform'
require_relative 'types/props/private/deserializer_generator'
require_relative 'types/props/private/serializer_generator'
require_relative 'types/props/serializable'
require_relative 'types/props/type_validation'
require_relative 'types/props/private/parser'
require_relative 'types/props/generated_code_validation'

require_relative 'types/struct'

require_relative 'types/compatibility_patches'
