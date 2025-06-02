#ifndef RUBY_ABI_H
#define RUBY_ABI_H

#ifdef RUBY_ABI_VERSION /* should match the definition in config.h */

/* This number represents Ruby's ABI version.
 *
 * In development Ruby, it should be bumped every time an ABI incompatible
 * change is introduced. This will force other developers to rebuild extension
 * gems.
 *
 * The following cases are considered as ABI incompatible changes:
 * - Changing any data structures.
 * - Changing macros or inline functions causing a change in behavior.
 * - Deprecating or removing function declarations.
 *
 * The following cases are NOT considered as ABI incompatible changes:
 * - Any changes that does not involve the header files in the `include`
 *   directory.
 * - Adding macros, inline functions, or function declarations.
 * - Backwards compatible refactors.
 * - Editing comments.
 *
 * In released versions of Ruby, this number is not defined since teeny
 * versions of Ruby should guarantee ABI compatibility.
 */
#define RUBY_ABI_VERSION 0

/* Windows does not support weak symbols so ruby_abi_version will not exist
 * in the shared library. */
#if defined(HAVE_FUNC_WEAK) && !defined(_WIN32) && !defined(__MINGW32__) && !defined(__CYGWIN__)
# define RUBY_DLN_CHECK_ABI
#endif
#endif  /* RUBY_ABI_VERSION */

#ifdef RUBY_DLN_CHECK_ABI

# ifdef __cplusplus
extern "C" {
# endif

RUBY_FUNC_EXPORTED unsigned long long __attribute__((weak))
ruby_abi_version(void)
{
# ifdef RUBY_ABI_VERSION
    return RUBY_ABI_VERSION;
# else
    return 0;
# endif
}

# ifdef __cplusplus
}
# endif

#endif

#endif
