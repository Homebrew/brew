#ifndef RUBY_INTERNAL_ENCODING_ENCODING_H            /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_INTERNAL_ENCODING_ENCODING_H
/**
 * @file
 * @author     Ruby developers <ruby-core@ruby-lang.org>
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @warning    Symbols   prefixed  with   either  `RBIMPL`   or  `rbimpl`   are
 *             implementation details.   Don't take  them as canon.  They could
 *             rapidly appear then vanish.  The name (path) of this header file
 *             is also an  implementation detail.  Do not expect  it to persist
 *             at the place it is now.  Developers are free to move it anywhere
 *             anytime at will.
 * @note       To  ruby-core:  remember  that   this  header  can  be  possibly
 *             recursively included  from extension  libraries written  in C++.
 *             Do not  expect for  instance `__VA_ARGS__` is  always available.
 *             We assume C99  for ruby itself but we don't  assume languages of
 *             extension libraries.  They could be written in C++98.
 * @brief      Defines ::rb_encoding
 */

#include "ruby/oniguruma.h"
#include "ruby/internal/attr/const.h"
#include "ruby/internal/attr/deprecated.h"
#include "ruby/internal/attr/noalias.h"
#include "ruby/internal/attr/pure.h"
#include "ruby/internal/attr/returns_nonnull.h"
#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"
#include "ruby/internal/core/rbasic.h"
#include "ruby/internal/fl_type.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/**
 * `Encoding` class.
 *
 * @ingroup object
 */
RUBY_EXTERN VALUE rb_cEncoding;

/**
 * @private
 *
 * Bit constants used when embedding encodings into ::RBasic::flags.  Extension
 * libraries must not bother such things.
 */
enum ruby_encoding_consts {

    /** Max possible number of embeddable encodings. */
    RUBY_ENCODING_INLINE_MAX = 127,

    /** Where inline encodings reside. */
    RUBY_ENCODING_SHIFT = (RUBY_FL_USHIFT+10),

    /** Bits we use to store inline encodings. */
    RUBY_ENCODING_MASK = (RUBY_ENCODING_INLINE_MAX<<RUBY_ENCODING_SHIFT
                          /* RUBY_FL_USER10..RUBY_FL_USER16 */),

    /** Max possible length of an encoding name. */
    RUBY_ENCODING_MAXNAMELEN = 42
};

#define ENCODING_INLINE_MAX RUBY_ENCODING_INLINE_MAX /**< @old{RUBY_ENCODING_INLINE_MAX} */
#define ENCODING_SHIFT RUBY_ENCODING_SHIFT           /**< @old{RUBY_ENCODING_SHIFT} */
#define ENCODING_MASK RUBY_ENCODING_MASK             /**< @old{RUBY_ENCODING_MASK} */

/**
 * Destructively assigns the passed encoding  to the passed object.  The object
 * must be  capable of  having inline  encoding.  Using  this macro  needs deep
 * understanding of bit level object binary layout.
 *
 * @param[out]  obj      Target object to modify.
 * @param[in]   ecindex  Encoding in encindex format.
 * @post        `obj`'s encoding is `encindex`.
 */
static inline void
RB_ENCODING_SET_INLINED(VALUE obj, int encindex)
{
    VALUE f = /* upcast */ encindex;

    f <<= RUBY_ENCODING_SHIFT;
    RB_FL_UNSET_RAW(obj, RUBY_ENCODING_MASK);
    RB_FL_SET_RAW(obj, f);
}

/**
 * Queries the  encoding of the  passed object.   The encoding must  be smaller
 * than ::RUBY_ENCODING_INLINE_MAX, which means you have some assumption on the
 * return value.  This means the API is for internal use only.
 *
 * @param[in]  obj  Target object.
 * @return     `obj`'s encoding index.
 */
static inline int
RB_ENCODING_GET_INLINED(VALUE obj)
{
    VALUE ret = RB_FL_TEST_RAW(obj, RUBY_ENCODING_MASK) >> RUBY_ENCODING_SHIFT;

    return RBIMPL_CAST((int)ret);
}

#define ENCODING_SET_INLINED(obj,i) RB_ENCODING_SET_INLINED(obj,i) /**< @old{RB_ENCODING_SET_INLINED} */
#define ENCODING_SET(obj,i) RB_ENCODING_SET(obj,i)                 /**< @old{RB_ENCODING_SET} */
#define ENCODING_GET_INLINED(obj) RB_ENCODING_GET_INLINED(obj)     /**< @old{RB_ENCODING_GET_INLINED} */
#define ENCODING_GET(obj) RB_ENCODING_GET(obj)                     /**< @old{RB_ENCODING_GET} */
#define ENCODING_IS_ASCII8BIT(obj) RB_ENCODING_IS_ASCII8BIT(obj)   /**< @old{RB_ENCODING_IS_ASCII8BIT} */
#define ENCODING_MAXNAMELEN RUBY_ENCODING_MAXNAMELEN               /**< @old{RUBY_ENCODING_MAXNAMELEN} */

/**
 * The  type  of encoding.   Our  design  here  is we  take  Oniguruma/Onigmo's
 * multilingualisation schema as our base data structure.
 */
typedef const OnigEncodingType rb_encoding;

RBIMPL_ATTR_NOALIAS()
/**
 * Converts  a character  option  to its  encoding.  It  only  supports a  very
 * limited set  of Japanese encodings due  to its Japanese origin.   Ruby still
 * has this in-core for backwards compatibility.  But new codes must not bother
 * such  concept like  one-character encoding  option.  Consider  deprecated in
 * practice.
 *
 * @param[in]   c       One of `['n', 'e', 's', 'u', 'i', 'x', 'm']`.
 * @param[out]  option  Return buffer.
 * @param[out]  kcode   Return buffer.
 * @retval      1       `c` understood properly.
 * @retval      0       `c` is not understood.
 * @post        `option` is a ::OnigOptionType.
 * @post        `kcode` is an enum `ruby_preserved_encindex`.
 *
 * @internal
 *
 * `kcode`  is opaque  because  `ruby_preserved_encindex` is  not visible  from
 * extension libraries.  But who cares?
 */
int rb_char_to_option_kcode(int c, int *option, int *kcode);

/**
 * Creates a new encoding, using the passed one as a template.
 *
 * @param[in]  name          Name of the creating encoding.
 * @param[in]  src           Template.
 * @exception  rb_eArgError  Duplicated or malformed `name`.
 * @return     Replicated new encoding's index.
 * @post       Encoding named `name` is created as a copy of `src`, whose index
 *             is the return value.
 *
 * @internal
 *
 * `name` can be `NULL`,  but that just raises an exception.   OTOH it seems no
 * sanity check is done against `src`...?
 */
int rb_enc_replicate(const char *name, rb_encoding *src);

/**
 * Creates a new "dummy" encoding.  Roughly speaking, an encoding is dummy when
 * it is  stateful.  Notable  example of  dummy encoding  are those  defined in
 * ISO/IEC 2022
 *
 * @param[in]  name  Name of the creating encoding.
 * @exception  rb_eArgError  Duplicated or malformed `name`.
 * @return     New dummy encoding's index.
 * @post       Encoding  named `name`  is created,  whose index  is the  return
 *             value.
 */
int rb_define_dummy_encoding(const char *name);

RBIMPL_ATTR_PURE()
/**
 * Queries if the passed encoding is dummy.
 *
 * @param[in]  enc  Encoding in question.
 * @retval     1    It is.
 * @retval     0    It isn't.
 */
int rb_enc_dummy_p(rb_encoding *enc);

RBIMPL_ATTR_PURE()
/**
 * Queries the  index of  the encoding.   An encoding's  index is  a Ruby-local
 * concept.  It is a (sequential) number assigned to each encoding.
 *
 * @param[in]  enc  Encoding in question.
 * @return     Its index.
 * @note       You can pass  null pointers to this function.   It is equivalent
 *             to rb_usascii_encindex() then.
 */
int rb_enc_to_index(rb_encoding *enc);

/**
 * Queries the index of the encoding of the passed object, if any.
 *
 * @param[in]  obj        Object in question.
 * @retval     -1         `obj` is incapable of having an encoding.
 * @retval     otherwise  `obj`'s encoding's index.
 */
int rb_enc_get_index(VALUE obj);

/**
 * @alias{rb_enc_get_index}
 *
 * @internal
 *
 * Implementation wise this is not a verbatim alias of rb_enc_get_index().  But
 * the API is consistent.  Don't bother.
 */
static inline int
RB_ENCODING_GET(VALUE obj)
{
    int encindex = RB_ENCODING_GET_INLINED(obj);

    if (encindex == RUBY_ENCODING_INLINE_MAX) {
        return rb_enc_get_index(obj);
    }
    else {
        return encindex;
    }
}

/**
 * Destructively assigns an encoding (via its index) to an object.
 *
 * @param[out]  obj                Object in question.
 * @param[in]   encindex           An encoding index.
 * @exception   rb_eFrozenError    `obj` is frozen.
 * @exception   rb_eArgError       `obj` is incapable of having an encoding.
 * @exception   rb_eEncodingError  `encindex` is out of bounds.
 * @exception   rb_eLoadError      Failed to load the encoding.
 */
void rb_enc_set_index(VALUE obj, int encindex);

/** @alias{rb_enc_set_index} */
static inline void
RB_ENCODING_SET(VALUE obj, int encindex)
{
    rb_enc_set_index(obj, encindex);
}

/**
 * This is #RB_ENCODING_SET  + RB_ENC_CODERANGE_SET combo.  The  object must be
 * capable  of   having  inline   encoding.   Using   this  macro   needs  deep
 * understanding of bit level object binary layout.
 *
 * @param[out]  obj       Target object.
 * @param[in]   encindex  Encoding in encindex format.
 * @param[in]   cr        An enum ::ruby_coderange_type.
 * @post        `obj`'s encoding is `encindex`.
 * @post        `obj`'s code range is `cr`.
 */
static inline void
RB_ENCODING_CODERANGE_SET(VALUE obj, int encindex, enum ruby_coderange_type cr)
{
    RB_ENCODING_SET(obj, encindex);
    RB_ENC_CODERANGE_SET(obj, cr);
}

RBIMPL_ATTR_PURE()
/**
 * Queries if the passed object can have its encoding.
 *
 * @param[in]  obj  Object in question.
 * @retval     1    It can.
 * @retval     0    It cannot.
 */
int rb_enc_capable(VALUE obj);

/**
 * Queries the index of the encoding.
 *
 * @param[in]  name          Name of the encoding to find.
 * @exception  rb_eArgError  No such encoding named `name`.
 * @retval     -1            `name` exists, but unable to load.
 * @retval     otherwise     Index of encoding named `name`.
 */
int rb_enc_find_index(const char *name);

/**
 * Registers an  "alias" name.  In  the wild, an  encoding can be  called using
 * multiple names.  For instance an encoding  known as `"CP932"` is also called
 * `"SJIS"` on occasions.  This API registers such relationships.
 *
 * @param[in]  alias         New name.
 * @param[in]  orig          Old name.
 * @exception  rb_eArgError  `alias` is duplicated or malformed.
 * @retval     -1            Failed to load `orig`.
 * @retval     otherwise     The index of `orig` and `alias`.
 * @post       `alias` is  a synonym  of `orig`.  They  refer to  the identical
 *             encoding.
 */
int rb_enc_alias(const char *alias, const char *orig);

/**
 * Obtains   a  encoding   index  from   a   wider  range   of  objects   (than
 * rb_enc_find_index()).
 *
 * @param[in]  obj        An ::rb_cEncoding, or its name in ::rb_cString.
 * @retval     -1         `obj` is unexpected type/contents.
 * @retval     otherwise  Index corresponding to `obj`.
 */
int rb_to_encoding_index(VALUE obj);

/**
 * Identical to  rb_find_encoding(), except it  raises an exception  instead of
 * returning NULL.
 *
 * @param[in]  obj            An ::rb_cEncoding, or its name in ::rb_cString.
 * @exception  rb_eTypeError  `obj` is neither ::rb_cEncoding nor ::rb_cString.
 * @exception  rb_eArgError   `obj` is an unknown encoding name.
 * @return     Encoding of `obj`.
 */
rb_encoding *rb_to_encoding(VALUE obj);

/**
 * Identical to rb_to_encoding_index(), except the return type.
 *
 * @param[in]  obj            An ::rb_cEncoding, or its name in ::rb_cString.
 * @exception  rb_eTypeError  `obj` is neither ::rb_cEncoding nor ::rb_cString.
 * @retval     NULL           No such encoding.
 * @return     otherwise      Encoding of `obj`.
 */
rb_encoding *rb_find_encoding(VALUE obj);

/**
 * Identical to rb_enc_get_index(), except the return type.
 *
 * @param[in]  obj        Object in question.
 * @retval     NULL       Obj is incapable of having an encoding.
 * @retval     otherwise  `obj`'s encoding.
 */
rb_encoding *rb_enc_get(VALUE obj);

/**
 * Look for the "common" encoding between the two.  One character can or cannot
 * be expressed depending on an encoding.  This function finds the super-set of
 * encodings that  satisfy contents of  both arguments.  If that  is impossible
 * returns NULL.
 *
 * @param[in]  str1       An object.
 * @param[in]  str2       Another object.
 * @retval     NULL       No encoding can satisfy both at once.
 * @retval     otherwise  Common encoding between the two.
 * @note       Arguments can be non-string, e.g. Regexp.
 */
rb_encoding *rb_enc_compatible(VALUE str1, VALUE str2);

/**
 * Identical to rb_enc_compatible(),  except it raises an  exception instead of
 * returning NULL.
 *
 * @param[in]  str1                An object.
 * @param[in]  str2                Another object.
 * @exception  rb_eEncCompatError  No encoding can satisfy both.
 * @return     Common encoding between the two.
 * @note       Arguments can be non-string, e.g. Regexp.
 */
rb_encoding *rb_enc_check(VALUE str1,VALUE str2);

/**
 * Identical to rb_enc_set_index(), except it additionally does contents fix-up
 * depending on the passed object.  It  for instance changes the byte length of
 * terminating `U+0000` according to the passed encoding.
 *
 * @param[out]  obj                Object in question.
 * @param[in]   encindex           An encoding index.
 * @exception   rb_eFrozenError    `obj` is frozen.
 * @exception   rb_eArgError       `obj` is incapable of having an encoding.
 * @exception   rb_eEncodingError  `encindex` is out of bounds.
 * @exception   rb_eLoadError      Failed to load the encoding.
 * @return      The passed `obj`.
 * @post        `obj`'s contents might be fixed according to `encindex`.
 */
VALUE rb_enc_associate_index(VALUE obj, int encindex);

/**
 * Identical to rb_enc_associate(), except it  takes an encoding itself instead
 * of its index.
 *
 * @param[out]  obj                Object in question.
 * @param[in]   enc                An encoding.
 * @exception   rb_eFrozenError    `obj` is frozen.
 * @exception   rb_eArgError       `obj` is incapable of having an encoding.
 * @return      The passed `obj`.
 * @post        `obj`'s contents might be fixed according to `enc`.
 */
VALUE rb_enc_associate(VALUE obj, rb_encoding *enc);

/**
 * Destructively copies  the encoding of  the latter  object to that  of former
 * one.     It   can    also   be    seen   as    a   routine    identical   to
 * rb_enc_associate_index(), except it takes an object's encoding instead of an
 * encoding's index.
 *
 * @param[out]  dst                Object to modify.
 * @param[in]   src                Object to reference.
 * @exception   rb_eFrozenError    `dst` is frozen.
 * @exception   rb_eArgError       `dst` is incapable of having an encoding.
 * @exception   rb_eEncodingError  `src` is incapable of having an encoding.
 * @post        `dst`'s encoding is that of `src`'s.
 */
void rb_enc_copy(VALUE dst, VALUE src);


/**
 * Identical to rb_find_encoding(),  except it takes an  encoding index instead
 * of a Ruby object.
 *
 * @param[in]  idx        An encoding index.
 * @retval     NULL       No such encoding.
 * @retval     otherwise  An encoding whose index is `idx`.
 */
rb_encoding *rb_enc_from_index(int idx);

/**
 * Identical to  rb_find_encoding(), except  it takes a  C's string  instead of
 * Ruby's.
 *
 * @param[in]  name       Name of the encoding to query.
 * @retval     NULL       No such encoding.
 * @retval     otherwise  An encoding whose index is `idx`.
 */
rb_encoding *rb_enc_find(const char *name);

/**
 * Queries the (canonical) name of the passed encoding.
 *
 * @param[in]  enc  An encoding.
 * @return     Its name.
 */
static inline const char *
rb_enc_name(rb_encoding *enc)
{
    return enc->name;
}

/**
 * Queries  the minimum  number  of bytes  that the  passed  encoding needs  to
 * represent a character.  For ASCII and compatible encodings this is typically
 * 1.   There  are  however  encodings  whose   minimum  is  not  1;  they  are
 * historically called wide characters.
 *
 * @param[in]  enc  An encoding.
 * @return     Its least possible number of bytes except 0.
 */
static inline int
rb_enc_mbminlen(rb_encoding *enc)
{
    return enc->min_enc_len;
}

/**
 * Queries  the maximum  number  of bytes  that the  passed  encoding needs  to
 * represent a character.   Fixed-width encodings have the same  value for this
 * one  and  #rb_enc_mbminlen.   However there  are  variable-width  encodings.
 * UTF-8, for instance, takes from 1 up to 6 bytes.
 *
 * @param[in]  enc  An encoding.
 * @return     Its maximum possible number of bytes of a character.
 */
static inline int
rb_enc_mbmaxlen(rb_encoding *enc)
{
    return enc->max_enc_len;
}

/**
 * Queries the number of bytes of the character at the passed pointer.
 *
 * @param[in]  p    Pointer to a character's first byte.
 * @param[in]  e    End of the string that has `p`.
 * @param[in]  enc  Encoding of the string.
 * @return     If the character at `p` does  not end until `e`, number of bytes
 *             between `p`  and `e`.   Otherwise the number  of bytes  that the
 *             character at `p` is encoded.
 *
 * @internal
 *
 * Strictly speaking there  are chances when `p`  points to a middle  byte of a
 * wide character.   This function  returns "the  number of  bytes from  `p` to
 * nearest of either `e` or the next character boundary", if you go strict.
 */
int rb_enc_mbclen(const char *p, const char *e, rb_encoding *enc);

/**
 * Identical to rb_enc_mbclen() unless the character at `p` overruns `e`.  That
 * can happen  for instance when  you read from a  socket and its  partial read
 * cuts  a  wide  character  in-between.  In  those  situations  this  function
 * "estimates" theoretical length  of the character in  question.  Typically it
 * tends  to be  possible  to know  how  many bytes  a  character needs  before
 * actually reaching its  end; for instance UTF-8 encodes  a character's length
 * in the first byte of it.  This function returns that info.
 *
 * @note  This implies that the string is not broken.
 *
 * @param[in]  p    Pointer to the character's first byte.
 * @param[in]  e    End of the string that has `p`.
 * @param[in]  enc  Encoding of the string.
 * @return     Number of bytes of character at `p`, measured or estimated.
 */
int rb_enc_fast_mbclen(const char *p, const char *e, rb_encoding *enc);

/**
 * Queries the  number of bytes of  the character at the  passed pointer.  This
 * function returns 3 different types of information:
 *
 * ```CXX
 * auto n = rb_enc_precise_mbclen(p, q, r);
 *
 * if (ONIGENC_MBCLEN_CHARFOUND_P(n)) {
 *     // Character found.  Normal return.
 *     auto found_length = ONIGENC_MBCLEN_CHARFOUND_LEN(n);
 * }
 * else if (ONIGENC_MBCLEN_NEEDMORE_P(n)) {
 *     // Character overruns past `q`; needs more.
 *     auto requested_length = ONIGENC_MBCLEN_NEEDMORE_LEN(n);
 * }
 * else {
 *     // `p` is broken.
 *     assert(ONIGENC_MBCLEN_INVALID_P(n));
 * }
 * ```
 *
 * @param[in]  p    Pointer to the character's first byte.
 * @param[in]  e    End of the string that has `p`.
 * @param[in]  enc  Encoding of the string.
 * @return     Encoded read/needed number of bytes (see above).
 */
int rb_enc_precise_mbclen(const char *p, const char *e, rb_encoding *enc);

#define MBCLEN_CHARFOUND_P(ret)   ONIGENC_MBCLEN_CHARFOUND_P(ret)   /**< @old{ONIGENC_MBCLEN_CHARFOUND_P} */
#define MBCLEN_CHARFOUND_LEN(ret) ONIGENC_MBCLEN_CHARFOUND_LEN(ret) /**< @old{ONIGENC_MBCLEN_CHARFOUND_LEN} */
#define MBCLEN_INVALID_P(ret)     ONIGENC_MBCLEN_INVALID_P(ret)     /**< @old{ONIGENC_MBCLEN_INVALID_P} */
#define MBCLEN_NEEDMORE_P(ret)    ONIGENC_MBCLEN_NEEDMORE_P(ret)    /**< @old{ONIGENC_MBCLEN_NEEDMORE_P} */
#define MBCLEN_NEEDMORE_LEN(ret)  ONIGENC_MBCLEN_NEEDMORE_LEN(ret)  /**< @old{ONIGENC_MBCLEN_NEEDMORE_LEN} */

/**
 * Queries the code point of character  pointed by the passed pointer.  If that
 * code point is included in ASCII  that code point is returned.  Otherwise -1.
 * This can be different from just looking  at the first byte.  For instance it
 * reads 2 bytes in case of UTF-16BE.
 *
 * @param[in]  p          Pointer to the character's first byte.
 * @param[in]  e          End of the string that has `p`.
 * @param[in]  len        Return buffer.
 * @param[in]  enc        Encoding of the string.
 * @retval     -1         The character at `p` is not i ASCII.
 * @retval     otherwise  A code point of the character at `p`.
 * @post       `len` (if set) is the number of bytes of `p`.
 */
int rb_enc_ascget(const char *p, const char *e, int *len, rb_encoding *enc);

/**
 * Queries  the  code  point  of  character  pointed  by  the  passed  pointer.
 * Exceptions happen in case of broken input.
 *
 * @param[in]  p             Pointer to the character's first byte.
 * @param[in]  e             End of the string that has `p`.
 * @param[in]  len           Return buffer.
 * @param[in]  enc           Encoding of the string.
 * @exception  rb_eArgError  `p` is broken.
 * @return     Code point of the character pointed by `p`.
 * @post       `len` (if set) is the number of bytes of `p`.
 */
unsigned int rb_enc_codepoint_len(const char *p, const char *e, int *len, rb_encoding *enc);

/**
 * Queries  the  code  point  of  character  pointed  by  the  passed  pointer.
 * Exceptions happen in case of broken input.
 *
 * @deprecated  Use rb_enc_codepoint_len() instead.
 * @param[in]   p             Pointer to the character's first byte.
 * @param[in]   e             End of the string that has `p`.
 * @param[in]   enc           Encoding of the string.
 * @exception   rb_eArgError  `p` is broken.
 * @return      Code point of the character pointed by `p`.
 *
 * @internal
 *
 * @matz says in commit  91e5ba1cb865a2385d3e1cbfacd824496898e098 that the line
 * below  is a  "prototype for  obsolete function".   However even  today there
 * still are some use  cases of it throughout our repository.   It seems it has
 * its own niche.
 */
static inline unsigned int
rb_enc_codepoint(const char *p, const char *e, rb_encoding *enc)
{
    return rb_enc_codepoint_len(p, e, 0, enc);
    /*                               ^^^
     * This can be `NULL` in C, `nullptr` in C++, and `0` for both.
     * We choose the most portable one here.
     */
}


/**
 * Identical to rb_enc_codepoint(),  except it assumes the  passed character is
 * not broken.
 *
 * @param[in]   p    Pointer to the character's first byte.
 * @param[in]   e    End of the string that has `p`.
 * @param[in]   enc  Encoding of the string.
 * @return      Code point of the character pointed by `p`.
 */
static inline OnigCodePoint
rb_enc_mbc_to_codepoint(const char *p, const char *e, rb_encoding *enc)
{
    const OnigUChar *up = RBIMPL_CAST((const OnigUChar *)p);
    const OnigUChar *ue = RBIMPL_CAST((const OnigUChar *)e);

    return ONIGENC_MBC_TO_CODE(enc, up, ue);
}

/**
 * Queries the  number of bytes  requested to  represent the passed  code point
 * using the passed encoding.
 *
 * @param[in]  code          Code point in question.
 * @param[in]  enc           Encoding to convert the code into a byte sequence.
 * @exception  rb_eArgError  `enc` does not glean `code`.
 * @return     Number of bytes requested to represent `code` using `enc`.
 */
int rb_enc_codelen(int code, rb_encoding *enc);

/**
 * Identical to rb_enc_codelen(), except it returns 0 for invalid code points.
 *
 * @param[in]  c          Code point in question.
 * @param[in]  enc        Encoding to convert `c` into a byte sequence.
 * @retval     0          `c` is invalid.
 * @return     otherwise  Number of bytes needed for `enc` to encode `c`.
 */
static inline int
rb_enc_code_to_mbclen(int c, rb_encoding *enc)
{
    OnigCodePoint uc = RBIMPL_CAST((OnigCodePoint)c);

    return ONIGENC_CODE_TO_MBCLEN(enc, uc);
}

/**
 * Identical to rb_enc_uint_chr(),  except it writes back to  the passed buffer
 * instead of allocating one.
 *
 * @param[in]   c    Code point.
 * @param[out]  buf  Return buffer.
 * @param[in]   enc  Target encoding scheme.
 * @post        `c` is encoded according to `enc`, then written to `buf`.
 *
 * @internal
 *
 * The second argument  must be typed.  But its current  usages prevent us from
 * being any stricter than this. :FIXME:
 */
static inline int
rb_enc_mbcput(unsigned int c, void *buf, rb_encoding *enc)
{
    OnigCodePoint uc = RBIMPL_CAST((OnigCodePoint)c);
    OnigUChar *ubuf = RBIMPL_CAST((OnigUChar *)buf);

    return ONIGENC_CODE_TO_MBC(enc, uc, ubuf);
}

/**
 * Queries the previous (left) character.
 *
 * @param[in]  s          Start of the string.
 * @param[in]  p          Pointer to a character.
 * @param[in]  e          End of the string.
 * @param[in]  enc        Encoding.
 * @retval     NULL       No previous character.
 * @retval     otherwise  Pointer to the head of the previous character.
 */
static inline char *
rb_enc_prev_char(const char *s, const char *p, const char *e, rb_encoding *enc)
{
    const OnigUChar *us = RBIMPL_CAST((const OnigUChar *)s);
    const OnigUChar *up = RBIMPL_CAST((const OnigUChar *)p);
    const OnigUChar *ue = RBIMPL_CAST((const OnigUChar *)e);
    OnigUChar *ur = onigenc_get_prev_char_head(enc, us, up, ue);

    return RBIMPL_CAST((char *)ur);
}

/**
 * Queries the  left boundary of  a character.   This function takes  a pointer
 * that is not necessarily a head of a character, and searches for its head.
 *
 * @param[in]  s          Start of the string.
 * @param[in]  p          Pointer to a possibly-middle of a character.
 * @param[in]  e          End of the string.
 * @param[in]  enc        Encoding.
 * @return     Pointer to the head of the character that contains `p`.
 */
static inline char *
rb_enc_left_char_head(const char *s, const char *p, const char *e, rb_encoding *enc)
{
    const OnigUChar *us = RBIMPL_CAST((const OnigUChar *)s);
    const OnigUChar *up = RBIMPL_CAST((const OnigUChar *)p);
    const OnigUChar *ue = RBIMPL_CAST((const OnigUChar *)e);
    OnigUChar *ur = onigenc_get_left_adjust_char_head(enc, us, up, ue);

    return RBIMPL_CAST((char *)ur);
}

/**
 * Queries the  right boundary of a  character.  This function takes  a pointer
 * that is not necessarily a head of a character, and searches for its tail.
 *
 * @param[in]  s    Start of the string.
 * @param[in]  p    Pointer to a possibly-middle of a character.
 * @param[in]  e    End of the string.
 * @param[in]  enc  Encoding.
 * @return     Pointer to the end of the character that contains `p`.
 */
static inline char *
rb_enc_right_char_head(const char *s, const char *p, const char *e, rb_encoding *enc)
{
    const OnigUChar *us = RBIMPL_CAST((const OnigUChar *)s);
    const OnigUChar *up = RBIMPL_CAST((const OnigUChar *)p);
    const OnigUChar *ue = RBIMPL_CAST((const OnigUChar *)e);
    OnigUChar *ur = onigenc_get_right_adjust_char_head(enc, us, up, ue);

    return RBIMPL_CAST((char *)ur);
}

/**
 * Scans the string backwards for n characters.
 *
 * @param[in]  s          Start of the string.
 * @param[in]  p          Pointer to a character.
 * @param[in]  e          End of the string.
 * @param[in]  n          Steps.
 * @param[in]  enc        Encoding.
 * @retval     NULL       There are no `n` characters left.
 * @retval     otherwise  Pointer to `n` character before `p`.
 */
static inline char *
rb_enc_step_back(const char *s, const char *p, const char *e, int n, rb_encoding *enc)
{
    const OnigUChar *us = RBIMPL_CAST((const OnigUChar *)s);
    const OnigUChar *up = RBIMPL_CAST((const OnigUChar *)p);
    const OnigUChar *ue = RBIMPL_CAST((const OnigUChar *)e);
    const OnigUChar *ur = onigenc_step_back(enc, us, up, ue, n);

    return RBIMPL_CAST((char *)ur);
}

/**
 * @private
 *
 * This is an implementation detail  of rb_enc_asciicompat().  People don't use
 * it directly.  Just always use rb_enc_asciicompat().
 *
 * @param[in]  enc  Encoding in question.
 * @retval     1    It is ASCII compatible.
 * @retval     0    It isn't.
 */
static inline int
rb_enc_asciicompat_inline(rb_encoding *enc)
{
    return rb_enc_mbminlen(enc)==1 && !rb_enc_dummy_p(enc);
}

/**
 * Queries if  the passed encoding  is _in  some sense_ compatible  with ASCII.
 * The  concept  of  ASCII  compatibility   is  nuanced,  and  private  to  our
 * implementation.  For instance SJIS is  ASCII compatible to us, despite their
 * having different  characters at code  point `0x5C`.   This is based  on some
 * practical  consideration that  Japanese people  confuses SJIS  to be  "upper
 * compatible" with ASCII (which is in fact  a wrong idea, but we just don't go
 * strict here).  An example of  ASCII incompatible encoding is UTF-16.  UTF-16
 * shares code points  with ASCII, but employs a  completely different encoding
 * scheme.
 *
 * @param[in]  enc  Encoding in question.
 * @retval     0    It is incompatible.
 * @retval     1    It is compatible.
 */
static inline bool
rb_enc_asciicompat(rb_encoding *enc)
{
    if (rb_enc_mbminlen(enc) != 1) {
        return false;
    }
    else if (rb_enc_dummy_p(enc)) {
        return false;
    }
    else {
        return true;
    }
}

/**
 * Queries if the passed string is in an ASCII-compatible encoding.
 *
 * @param[in]  str  A Ruby's string to query.
 * @retval     0    `str` is not a String, or an ASCII-incompatible string.
 * @retval     1    Otherwise.
 */
static inline bool
rb_enc_str_asciicompat_p(VALUE str)
{
    rb_encoding *enc = rb_enc_get(str);

    return rb_enc_asciicompat(enc);
}

/**
 * Queries  the   Ruby-level  counterpart   instance  of   ::rb_cEncoding  that
 * corresponds to the passed encoding.
 *
 * @param[in]  enc  An encoding
 * @retval     RUBY_Qnil  `enc` is a null pointer.
 * @retval     otherwise  An instance of ::rb_cEncoding.
 */
VALUE rb_enc_from_encoding(rb_encoding *enc);

RBIMPL_ATTR_PURE()
/**
 * Queries if the passed encoding is either one of UTF-8/16/32.
 *
 * @note  It does not take UTF-7, which we actually support, into account.
 *
 * @param[in]  enc        Encoding in question.
 * @retval     0          It is not a Unicode variant.
 * @retval     otherwise  It is.
 *
 * @internal
 *
 * In   reality   it   returns   1/0,   but  the   value   is   abstracted   as
 * `ONIGENC_FLAG_UNICODE`.
 */
int rb_enc_unicode_p(rb_encoding *enc);

RBIMPL_ATTR_RETURNS_NONNULL()
/**
 * Queries the encoding that represents ASCII-8BIT a.k.a. binary.
 *
 * @return  The encoding that represents ASCII-8BIT.
 *
 * @internal
 *
 * This can not return NULL once the process properly boots up.
 */
rb_encoding *rb_ascii8bit_encoding(void);

RBIMPL_ATTR_RETURNS_NONNULL()
/**
 * Queries the encoding that represents UTF-8.
 *
 * @return  The encoding that represents UTF-8.
 *
 * @internal
 *
 * This can not return NULL once the process properly boots up.
 */
rb_encoding *rb_utf8_encoding(void);

RBIMPL_ATTR_RETURNS_NONNULL()
/**
 * Queries the encoding that represents US-ASCII.
 *
 * @return  The encoding that represents US-ASCII.
 *
 * @internal
 *
 * This can not return NULL once the process properly boots up.
 */
rb_encoding *rb_usascii_encoding(void);

/**
 * Queries the encoding that represents the current locale.
 *
 * @return  The encoding that represents the process' locale.
 *
 * @internal
 *
 * This  is dynamic.   If  you  change the  process'  locale  by e.g.   calling
 * `setlocale(3)`, that should also change the return value of this function.
 *
 * There is no official way for Ruby scripts to manipulate locales, though.
 */
rb_encoding *rb_locale_encoding(void);

/**
 * Queries the "filesystem"  encoding.  This is the encoding  that ruby expects
 * info from  the OS'  file system  are in.  This  affects for  instance return
 * value of rb_dir_getwd().  Most  notably on Windows it can be  an alias of OS
 * codepage.  Most  notably on Linux  users can  set this via  default external
 * encoding.
 *
 * @return  The "filesystem" encoding.
 */
rb_encoding *rb_filesystem_encoding(void);

/**
 * Queries  the "default  external" encoding.   This is  used to  interact with
 * outer-process things such as File.  Though not recommended, you can set this
 * using rb_enc_set_default_external().
 *
 * @return  The "default external"  encoding.
 */
rb_encoding *rb_default_external_encoding(void);

/**
 * Queries  the "default  internal" encoding.   This could  be a  null pointer.
 * Otherwise, outer-process info are  transcoded from default external encoding
 * to this one during reading from an IO.
 *
 * @return  The "default internal"  encoding (if any).
 */
rb_encoding *rb_default_internal_encoding(void);

#ifndef rb_ascii8bit_encindex
RBIMPL_ATTR_CONST()
/**
 * Identical to rb_ascii8bit_encoding(), except it returns the encoding's index
 * instead of the encoding itself.
 *
 * @return  The index of encoding of ASCII-8BIT.
 *
 * @internal
 *
 * This happens to be 0.
 */
int rb_ascii8bit_encindex(void);
#endif

/**
 * Queries if  the passed  object is  in ascii 8bit  (== binary)  encoding. The
 * object must  be capable of having  inline encoding.  Using this  macro needs
 * deep understanding of bit level object binary layout.
 *
 * @param[in]  obj  An object to check.
 * @retval     1    It is.
 * @retval     0    It isn't.
 */
static inline bool
RB_ENCODING_IS_ASCII8BIT(VALUE obj)
{
    return RB_ENCODING_GET_INLINED(obj) == rb_ascii8bit_encindex();
}

#ifndef rb_utf8_encindex
RBIMPL_ATTR_CONST()
/**
 * Identical  to rb_utf8_encoding(),  except  it returns  the encoding's  index
 * instead of the encoding itself.
 *
 * @return  The index of encoding of UTF-8.
 */
int rb_utf8_encindex(void);
#endif

#ifndef rb_usascii_encindex
RBIMPL_ATTR_CONST()
/**
 * Identical to  rb_usascii_encoding(), except it returns  the encoding's index
 * instead of the encoding itself.
 *
 * @return  The index of encoding of UTF-8.
 */
int rb_usascii_encindex(void);
#endif

/**
 * Identical to  rb_locale_encoding(), except  it returns the  encoding's index
 * instead of the encoding itself.
 *
 * @return  The index of the locale encoding.
 */
int rb_locale_encindex(void);

/**
 * Identical  to rb_filesystem_encoding(),  except  it  returns the  encoding's
 * index instead of the encoding itself.
 *
 * @return  The index of the filesystem encoding.
 */
int rb_filesystem_encindex(void);

/**
 * Identical   to  rb_default_external_encoding(),   except   it  returns   the
 * Ruby-level counterpart  instance of  ::rb_cEncoding that corresponds  to the
 * default external encoding.
 *
 * @return  An instance of ::rb_cEncoding of default external.
 */
VALUE rb_enc_default_external(void);

/**
 * Identical   to  rb_default_internal_encoding(),   except   it  returns   the
 * Ruby-level counterpart  instance of  ::rb_cEncoding that corresponds  to the
 * default internal encoding.
 *
 * @return  An instance of ::rb_cEncoding of default internal.
 */
VALUE rb_enc_default_internal(void);

/**
 * Destructively assigns the passed encoding  as the default external encoding.
 * You should not  use this API.  It has process-global  side effects.  Also it
 * doesn't change encodings of strings that have already been read.
 *
 * @param[in]  encoding      Ruby level encoding.
 * @exception  rb_eArgError  `encoding` is ::RUBY_Qnil.
 * @post       The default external encoding is `encoding`.
 */
void rb_enc_set_default_external(VALUE encoding);

/**
 * Destructively assigns the passed encoding  as the default internal encoding.
 * You should not  use this API.  It has process-global  side effects.  Also it
 * doesn't change encodings of strings that have already been read.
 *
 * @param[in]  encoding      Ruby level encoding.
 * @post       The default internal encoding is `encoding`.
 * @note       Unlike rb_enc_set_default_external() you can pass ::RUBY_Qnil.
 */
void rb_enc_set_default_internal(VALUE encoding);

/**
 * Returns  a   platform-depended  "charmap"  of  the   current  locale.   This
 * information  is  called   a  "Codeset  name"  in  IEEE   1003.1  section  13
 * (`<langinfo.h>`).  This is a very low-level  API.  The return value can have
 * no corresponding encoding when passed to rb_find_encoding().
 *
 * @param[in]  klass  Ignored for no reason (why...)
 * @return     The low-level locale charmap, in Ruby's String.
 */
VALUE rb_locale_charmap(VALUE klass);

RBIMPL_SYMBOL_EXPORT_END()

/** @cond INTERNAL_MACRO */
#define RB_ENCODING_GET          RB_ENCODING_GET
#define RB_ENCODING_GET_INLINED  RB_ENCODING_GET_INLINED
#define RB_ENCODING_IS_ASCII8BIT RB_ENCODING_IS_ASCII8BIT
#define RB_ENCODING_SET          RB_ENCODING_SET
#define RB_ENCODING_SET_INLINED  RB_ENCODING_SET_INLINED
#define rb_enc_asciicompat       rb_enc_asciicompat
#define rb_enc_code_to_mbclen    rb_enc_code_to_mbclen
#define rb_enc_codepoint         rb_enc_codepoint
#define rb_enc_left_char_head    rb_enc_left_char_head
#define rb_enc_mbc_to_codepoint  rb_enc_mbc_to_codepoint
#define rb_enc_mbcput            rb_enc_mbcput
#define rb_enc_mbmaxlen          rb_enc_mbmaxlen
#define rb_enc_mbminlen          rb_enc_mbminlen
#define rb_enc_name              rb_enc_name
#define rb_enc_prev_char         rb_enc_prev_char
#define rb_enc_right_char_head   rb_enc_right_char_head
#define rb_enc_step_back         rb_enc_step_back
#define rb_enc_str_asciicompat_p rb_enc_str_asciicompat_p
/** @endcond */

#endif /* RUBY_INTERNAL_ENCODING_ENCODING_H */
