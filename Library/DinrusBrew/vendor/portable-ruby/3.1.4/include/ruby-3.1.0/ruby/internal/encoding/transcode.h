#ifndef RUBY_INTERNAL_ENCODING_TRANSCODE_H           /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_INTERNAL_ENCODING_TRANSCODE_H
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
 * @brief      econv stuff
 */

#include "ruby/internal/dllexport.h"
#include "ruby/internal/value.h"

RBIMPL_SYMBOL_EXPORT_BEGIN()

/** return value of rb_econv_convert() */
typedef enum {

    /**
     * The conversion stopped when it found an invalid sequence.
     */
    econv_invalid_byte_sequence,

    /**
     * The conversion  stopped when  it found  a character  in the  input which
     * cannot be representable in the output.
     */
    econv_undefined_conversion,

    /**
     * The conversion stopped because there is no destination.
     */
    econv_destination_buffer_full,

    /**
     * The conversion stopped because there is no input.
     */
    econv_source_buffer_empty,

    /**
     * The conversion  stopped after  converting everything.  This  is arguably
     * the expected normal end of conversion.
     */
    econv_finished,

    /**
     * The  conversion stopped  after  writing something  to somewhere,  before
     * reading everything.
     */
    econv_after_output,

    /**
     * The conversion stopped in middle of reading a character, possibly due to
     * a partial read of a socket etc.
     */
    econv_incomplete_input
} rb_econv_result_t;

/** An opaque struct that represents a lowest level of encoding conversion. */
typedef struct rb_econv_t rb_econv_t;

/**
 * Converts the contents  of the passed string from its  encoding to the passed
 * one.
 *
 * @param[in]  str                           Target string.
 * @param[in]  to                            Destination encoding.
 * @param[in]  ecflags                       A        set        of        enum
 *                                           ::ruby_econv_flag_type.
 * @param[in]  ecopts                        A      keyword     hash,      like
 *                                           ::rb_io_t::rb_io_enc_t::ecopts.
 * @exception  rb_eArgError                  Not fully converted.
 * @exception  rb_eInvalidByteSequenceError  `str` is malformed.
 * @exception  rb_eUndefinedConversionError  `str`   has    a   character   not
 *                                           representable using `to`.
 * @exception  rb_eConversionNotFoundError   There is no  known conversion from
 *                                           `str`'s encoding to `to`.
 * @return     A string whose encoding is `to`, and whose contents is converted
 *             contents of `str`.
 * @note       Use rb_econv_prepare_options() to generate `ecopts`.
 */
VALUE rb_str_encode(VALUE str, VALUE to, int ecflags, VALUE ecopts);

/**
 * Queries if  there is  more than one  way to convert  between the  passed two
 * encodings.  Encoding  conversion are  has_and_belongs_to_many relationships.
 * There could be no direct conversion defined for the passed pair.  Ruby tries
 * to find  an indirect  way to  do so  then.  For  instance ISO-8859-1  has no
 * direct  conversion  to  ISO-2022-JP.   But  there  is  ISO-8859-1  to  UTF-8
 * conversion; then there is UTF-8 to  EUC-JP conversion; finally there also is
 * EUC-JP to ISO-2022-JP  conversion.  So in short ISO-8859-1  can be converted
 * to ISO-2022-JP using that path.   This function returns true.  Obviously not
 * everything that can be represented using UTF-8 can also be represented using
 * EUC-JP.  Conversions in practice can fail depending on the actual input, and
 * that renders exceptions in case of rb_str_encode().
 *
 * @param[in] from_encoding  One encoding.
 * @param[in] to_encoding    Another encoding.
 * @retval    0              No way to convert the two.
 * @retval    1              At least one way to convert the two.
 *
 * @internal
 *
 * Practically @shyouhei knows no way for  this function to return 0.  It seems
 * everything  can  eventually  be  converted  to/from  UTF-8,  which  connects
 * everything.
 */
int rb_econv_has_convpath_p(const char* from_encoding, const char* to_encoding);

/**
 * Identical  to  rb_econv_prepare_opts(),  except it  additionally  takes  the
 * initial  value of  flags.  The  extra bits  are bitwise-ORed  to the  return
 * value.
 *
 * @param[in]   opthash       Keyword arguments.
 * @param[out]  ecopts        Return buffer.
 * @param[in]   ecflags       Default set of enum ::ruby_econv_flag_type.
 * @exception   rb_eArgError  Unknown/Broken values passed.
 * @return      Calculated set of enum ::ruby_econv_flag_type.
 * @post        `ecopts`     holds    a     hash     object    suitable     for
 *              ::rb_io_t::rb_io_enc_t::ecopts.
 */
int rb_econv_prepare_options(VALUE opthash, VALUE *ecopts, int ecflags);

/**
 * Splits a  keyword arguments  hash (that  for instance  `String#encode` took)
 * into a  set of  enum ::ruby_econv_flag_type and  a hash  storing replacement
 * characters etc.
 *
 * @param[in]   opthash       Keyword arguments.
 * @param[out]  ecopts        Return buffer.
 * @exception   rb_eArgError  Unknown/Broken values passed.
 * @return      Calculated set of enum ::ruby_econv_flag_type.
 * @post        `ecopts`     holds    a     hash     object    suitable     for
 *              ::rb_io_t::rb_io_enc_t::ecopts.
 */
int rb_econv_prepare_opts(VALUE opthash, VALUE *ecopts);

/**
 * Creates a new instance of struct ::rb_econv_t.
 *
 * @param[in]  source_encoding       Name of an encoding.
 * @param[in]  destination_encoding  Name of another encoding.
 * @param[in]  ecflags               A set of enum ::ruby_econv_flag_type.
 * @exception  rb_eArgError          No such encoding.
 * @retval     NULL                  Failed to create a struct ::rb_econv_t.
 * @retval     otherwise             Allocated struct ::rb_econv_t.
 * @warning    Return value must be passed to rb_econv_close() exactly once.
 */
rb_econv_t *rb_econv_open(const char *source_encoding, const char *destination_encoding, int ecflags);

/**
 * Identical  to  rb_econv_open(),  except  it additionally  takes  a  hash  of
 * optional strings.
 *
 *
 * @param[in]  source_encoding       Name of an encoding.
 * @param[in]  destination_encoding  Name of another encoding.
 * @param[in]  ecflags               A set of enum ::ruby_econv_flag_type.
 * @param[in]  ecopts                Optional set of strings.
 * @exception  rb_eArgError          No such encoding.
 * @retval     NULL                  Failed to create a struct ::rb_econv_t.
 * @retval     otherwise             Allocated struct ::rb_econv_t.
 * @warning    Return value must be passed to rb_econv_close() exactly once.
 */
rb_econv_t *rb_econv_open_opts(const char *source_encoding, const char *destination_encoding, int ecflags, VALUE ecopts);

/**
 * Converts a string from an encoding to another.
 *
 * Possible  flags  are  either ::RUBY_ECONV_PARTIAL_INPUT  (means  the  source
 * buffer is a  part of much larger  one), ::RUBY_ECONV_AFTER_OUTPUT (instructs
 * the converter to stop after output before input), or both of them.
 *
 * @param[in,out]  ec                      Conversion specification/state etc.
 * @param[in]      source_buffer_ptr       Target string.
 * @param[in]      source_buffer_end       End of target string.
 * @param[out]     destination_buffer_ptr  Return buffer.
 * @param[out]     destination_buffer_end  End of return buffer.
 * @param[in]      flags                   Flags (see above).
 * @return         The status of the conversion.
 * @post           `destination_buffer_ptr` holds conversion results.
 */
rb_econv_result_t rb_econv_convert(rb_econv_t *ec,
    const unsigned char **source_buffer_ptr, const unsigned char *source_buffer_end,
    unsigned char **destination_buffer_ptr, unsigned char *destination_buffer_end,
    int flags);

/**
 * Destructs a converter.  Note that a converter  can have a buffer, and can be
 * non-empty.  Calling this would lose your data then.
 *
 * @param[out]  ec The converter to destroy.
 * @post        `ec` is no longer a valid pointer.
 */
void rb_econv_close(rb_econv_t *ec);

/**
 * Assigns  the replacement  string.  The  string passed  here would  appear in
 * converted string when it cannot  represent its source counterpart.  This can
 * happen for instance you convert an emoji to ISO-8859-1.
 *
 * @param[out]  ec       Target converter.
 * @param[in]   str      Replacement string.
 * @param[in]   len      Number of bytes of `str`.
 * @param[in]   encname  Name of encoding of `str`.
 * @retval      0        Success.
 * @retval      -1       Failure (ENOMEM etc.).
 * @post        `ec`'s replacement string is set to `str`.
 */
int rb_econv_set_replacement(rb_econv_t *ec, const unsigned char *str, size_t len, const char *encname);

/**
 * "Decorate"s  a  converter.   There  are  special  kind  of  converters  that
 * transforms the  contents, like  replacing CR  into CRLF.   You can  add such
 * decorators  to  a converter  using  this  API.   By  using this  function  a
 * decorator is prepended at the beginning of a conversion sequence: in case of
 * CRLF conversion, newlines are converted before encodings are converted.
 *
 * @param[out]  ec              Target converter to decorate.
 * @param[in]   decorator_name  Name of decorator to prepend.
 * @retval      0               Success.
 * @retval      -1              Failure (no such decorator etc.).
 * @post        Decorator works before encoding conversion happens.
 *
 * @internal
 *
 * What is the possible value of  the `decorator_name` is not public.  You have
 * to read through `transcode.c` carefully.
 */
int rb_econv_decorate_at_first(rb_econv_t *ec, const char *decorator_name);

/**
 * Identical to  rb_econv_decorate_at_first(), except  it adds to  the opposite
 * direction.  For  instance CRLF  conversion would  run _after_  encodings are
 * converted.
 *
 * @param[out]  ec              Target converter to decorate.
 * @param[in]   decorator_name  Name of decorator to prepend.
 * @retval      0               Success.
 * @retval      -1              Failure (no such decorator etc.).
 * @post        Decorator works after encoding conversion happens.
 */
int rb_econv_decorate_at_last(rb_econv_t *ec, const char *decorator_name);

/**
 * Creates  a  `rb_eConverterNotFoundError`  exception  object  (but  does  not
 * raise).
 *
 * @param[in]  senc     Name of source encoding.
 * @param[in]  denc     Name of destination encoding.
 * @param[in]  ecflags  A set of enum ::ruby_econv_flag_type.
 * @return     An instance of `rb_eConverterNotFoundError`.
 */
VALUE rb_econv_open_exc(const char *senc, const char *denc, int ecflags);

/**
 * Appends the passed string to the passed converter's output buffer.  This can
 * be  handy  when an  encoding  needs  bytes out  of  thin  air; for  instance
 * ISO-2022-JP  has  "shift   function"  which  does  not   correspond  to  any
 * characters.
 *
 * @param[out]  ec            Target converter.
 * @param[in]   str           String to insert.
 * @param[in]   len           Number of bytes of `str`.
 * @param[in]   str_encoding  Encoding of `str`.
 * @retval      0             Success.
 * @retval      -1            Failure (conversion error etc.).
 * @note        `str_encoding` can  be anything, and `str`  itself is converted
 *              when necessary.
 */
int rb_econv_insert_output(rb_econv_t *ec,
    const unsigned char *str, size_t len, const char *str_encoding);

/**
 * Queries  an encoding  name which  best suits  for rb_econv_insert_output()'s
 * last parameter.  Strings in this  encoding need no conversion when inserted;
 * can be both time/space efficient.
 *
 * @param[in]  ec  Target converter.
 * @return     Its encoding for insertion.
 */
const char *rb_econv_encoding_to_insert_output(rb_econv_t *ec);

/**
 * This is a rb_econv_make_exception() + rb_exc_raise() combo.
 *
 * @param[in]  ec                            (Possibly failed) conversion.
 * @exception  rb_eInvalidByteSequenceError  Invalid byte sequence.
 * @exception  rb_eUndefinedConversionError  Conversion undefined.
 * @note       This function can return when no error.
 */
void rb_econv_check_error(rb_econv_t *ec);

/**
 * This function makes sense right after rb_econv_convert() returns.  As listed
 * in ::rb_econv_result_t, rb_econv_convert() can bail out for various reasons.
 * This function checks the passed converter's internal state and convert it to
 * an appropriate exception object.
 *
 * @param[in]  ec         Target converter.
 * @retval     RUBY_Qnil  The converter has no error.
 * @retval     otherwise  Conversion error turned into an exception.
 */
VALUE rb_econv_make_exception(rb_econv_t *ec);

/**
 * Queries  if rb_econv_putback()  makes  sense, i.e.  there  are invalid  byte
 * sequences remain in the buffer.
 *
 * @param[in]  ec  Target converter.
 * @return     Number of bytes that can be pushed back.
 */
int rb_econv_putbackable(rb_econv_t *ec);

/**
 * Puts  back the  bytes.  In  case of  ::econv_invalid_byte_sequence, some  of
 * those  invalid  bytes are  discarded  and  the  others  are buffered  to  be
 * converted later.  The latter bytes can be put back using this API.
 *
 * @param[out]  ec  Target converter (invalid byte sequence).
 * @param[out]  p   Return buffer.
 * @param[in]   n   Max number of bytes to put back.
 * @post        At most `n` bytes of what was put back is written to `p`.
 */
void rb_econv_putback(rb_econv_t *ec, unsigned char *p, int n);

/**
 * Queries the passed encoding's corresponding ASCII compatible encoding.  "The
 * corresponding  ASCII  compatible  encoding"  in this  context  is  an  ASCII
 * compatible encoding which  can represent exactly the same  character sets as
 * the given  ASCII incompatible  encoding.  For instance  that of  UTF-16LE is
 * UTF-8.
 *
 * @param[in]  encname    Name of an ASCII incompatible encoding.
 * @retval     NULL       `encname` is already ASCII compatible.
 * @retval     otherwise  The corresponding ASCII compatible encoding.
 */
const char *rb_econv_asciicompat_encoding(const char *encname);

/**
 * Identical to  rb_econv_convert(), except it  takes Ruby's string  instead of
 * C's pointer.
 *
 * @param[in,out]  ec                            Target converter.
 * @param[in]      src                           Source string.
 * @param[in]      flags                         Flags (see rb_econv_convert).
 * @exception      rb_eArgError                  Converted string is too long.
 * @exception      rb_eInvalidByteSequenceError  Invalid byte sequence.
 * @exception      rb_eUndefinedConversionError  Conversion undefined.
 * @return         The conversion result.
 */
VALUE rb_econv_str_convert(rb_econv_t *ec, VALUE src, int flags);

/**
 * Identical to rb_econv_str_convert(),  except it converts only a  part of the
 * passed string.  Can be handy when  you for instance want to do line-buffered
 * conversion.
 *
 * @param[in,out]  ec                            Target converter.
 * @param[in]      src                           Source string.
 * @param[in]      byteoff                       Number of bytes to seek.
 * @param[in]      bytesize                      Number of bytes to read.
 * @param[in]      flags                         Flags (see rb_econv_convert).
 * @exception      rb_eArgError                  Converted string is too long.
 * @exception      rb_eInvalidByteSequenceError  Invalid byte sequence.
 * @exception      rb_eUndefinedConversionError  Conversion undefined.
 * @return         The conversion result.
 */
VALUE rb_econv_substr_convert(rb_econv_t *ec, VALUE src, long byteoff, long bytesize, int flags);

/**
 * Identical to rb_econv_str_convert(), except it appends the conversion result
 * to the additionally passed string instead  of creating a new string.  It can
 * also be seen as a routine  identical to rb_econv_append(), except it takes a
 * Ruby's string instead of C's pointer.
 *
 * @param[in,out]  ec                            Target converter.
 * @param[in]      src                           Source string.
 * @param[in]      dst                           Return buffer.
 * @param[in]      flags                         Flags (see rb_econv_convert).
 * @exception      rb_eArgError                  Converted string is too long.
 * @exception      rb_eInvalidByteSequenceError  Invalid byte sequence.
 * @exception      rb_eUndefinedConversionError  Conversion undefined.
 * @return         The conversion result.
 */
VALUE rb_econv_str_append(rb_econv_t *ec, VALUE src, VALUE dst, int flags);

/**
 * Identical to  rb_econv_str_append(), except  it appends only  a part  of the
 * passed string with  conversion.  It can also be seen  as a routine identical
 * to rb_econv_substr_convert(), except it appends the conversion result to the
 * additionally passed string instead of creating a new string.
 *
 * @param[in,out]  ec                            Target converter.
 * @param[in]      src                           Source string.
 * @param[in]      byteoff                       Number of bytes to seek.
 * @param[in]      bytesize                      Number of bytes to read.
 * @param[in]      dst                           Return buffer.
 * @param[in]      flags                         Flags (see rb_econv_convert).
 * @exception      rb_eArgError                  Converted string is too long.
 * @exception      rb_eInvalidByteSequenceError  Invalid byte sequence.
 * @exception      rb_eUndefinedConversionError  Conversion undefined.
 * @return         The conversion result.
 */
VALUE rb_econv_substr_append(rb_econv_t *ec, VALUE src, long byteoff, long bytesize, VALUE dst, int flags);

/**
 * Converts  the passed  C's pointer  according to  the passed  converter, then
 * append the conversion  result to the passed Ruby's string.   This way buffer
 * overflow is properly avoided to resize the destination properly.
 *
 * @param[in,out]  ec                            Target converter.
 * @param[in]      bytesrc                       Target string.
 * @param[in]      bytesize                      Number of bytes of `bytesrc`.
 * @param[in]      dst                           Return buffer.
 * @param[in]      flags                         Flags (see rb_econv_convert).
 * @exception      rb_eArgError                  Converted string is too long.
 * @exception      rb_eInvalidByteSequenceError  Invalid byte sequence.
 * @exception      rb_eUndefinedConversionError  Conversion undefined.
 * @return         The conversion result.
 */
VALUE rb_econv_append(rb_econv_t *ec, const char *bytesrc, long bytesize, VALUE dst, int flags);

/**
 * This badly named  function does not set the destination  encoding to binary,
 * but  instead just  nullifies newline  conversion decorators  if any.   Other
 * ordinal character conversions still  happen after this; something non-binary
 * would still be generated.
 *
 * @param[out]  ec  Target converter to modify.
 * @post        Any newline conversions, if any, would be killed.
 */
void rb_econv_binmode(rb_econv_t *ec);

/**
 * This enum is kind of omnibus.  Gathers various constants.
 */
enum ruby_econv_flag_type {

    /**
     * @name Flags for rb_econv_open()
     *
     * @{
     */

    /** Mask for error handling related bits. */
    RUBY_ECONV_ERROR_HANDLER_MASK               = 0x000000ff,

    /** Special handling of invalid sequences are there. */
    RUBY_ECONV_INVALID_MASK                     = 0x0000000f,

    /** Invalid sequences shall be replaced. */
    RUBY_ECONV_INVALID_REPLACE                  = 0x00000002,

    /** Special handling of undefined conversion are there. */
    RUBY_ECONV_UNDEF_MASK                       = 0x000000f0,

    /** Undefined characters shall be replaced. */
    RUBY_ECONV_UNDEF_REPLACE                    = 0x00000020,

    /** Undefined characters shall be escaped. */
    RUBY_ECONV_UNDEF_HEX_CHARREF                = 0x00000030,

    /** Decorators are there. */
    RUBY_ECONV_DECORATOR_MASK                   = 0x0000ff00,

    /** Newline converters are there. */
    RUBY_ECONV_NEWLINE_DECORATOR_MASK           = 0x00003f00,

    /** (Unclear; seems unused). */
    RUBY_ECONV_NEWLINE_DECORATOR_READ_MASK      = 0x00000f00,

    /** (Unclear; seems unused). */
    RUBY_ECONV_NEWLINE_DECORATOR_WRITE_MASK     = 0x00003000,

    /** Universal newline mode. */
    RUBY_ECONV_UNIVERSAL_NEWLINE_DECORATOR      = 0x00000100,

    /** CR to CRLF conversion shall happen. */
    RUBY_ECONV_CRLF_NEWLINE_DECORATOR           = 0x00001000,

    /** CRLF to CR conversion shall happen. */
    RUBY_ECONV_CR_NEWLINE_DECORATOR             = 0x00002000,

    /** Texts shall be XML-escaped. */
    RUBY_ECONV_XML_TEXT_DECORATOR               = 0x00004000,

    /** Texts shall be AttrValue escaped */
    RUBY_ECONV_XML_ATTR_CONTENT_DECORATOR       = 0x00008000,

    /** (Unclear; seems unused). */
    RUBY_ECONV_STATEFUL_DECORATOR_MASK          = 0x00f00000,

    /** Texts shall be AttrValue escaped. */
    RUBY_ECONV_XML_ATTR_QUOTE_DECORATOR         = 0x00100000,

    /** Newline decorator's default. */
    RUBY_ECONV_DEFAULT_NEWLINE_DECORATOR        =
#if defined(RUBY_TEST_CRLF_ENVIRONMENT) || defined(_WIN32)
        RUBY_ECONV_CRLF_NEWLINE_DECORATOR,
#else
        0,
#endif

#define ECONV_ERROR_HANDLER_MASK                RUBY_ECONV_ERROR_HANDLER_MASK           /**< @old{RUBY_ECONV_ERROR_HANDLER_MASK} */
#define ECONV_INVALID_MASK                      RUBY_ECONV_INVALID_MASK                 /**< @old{RUBY_ECONV_INVALID_MASK} */
#define ECONV_INVALID_REPLACE                   RUBY_ECONV_INVALID_REPLACE              /**< @old{RUBY_ECONV_INVALID_REPLACE} */
#define ECONV_UNDEF_MASK                        RUBY_ECONV_UNDEF_MASK                   /**< @old{RUBY_ECONV_UNDEF_MASK} */
#define ECONV_UNDEF_REPLACE                     RUBY_ECONV_UNDEF_REPLACE                /**< @old{RUBY_ECONV_UNDEF_REPLACE} */
#define ECONV_UNDEF_HEX_CHARREF                 RUBY_ECONV_UNDEF_HEX_CHARREF            /**< @old{RUBY_ECONV_UNDEF_HEX_CHARREF} */
#define ECONV_DECORATOR_MASK                    RUBY_ECONV_DECORATOR_MASK               /**< @old{RUBY_ECONV_DECORATOR_MASK} */
#define ECONV_NEWLINE_DECORATOR_MASK            RUBY_ECONV_NEWLINE_DECORATOR_MASK       /**< @old{RUBY_ECONV_NEWLINE_DECORATOR_MASK} */
#define ECONV_NEWLINE_DECORATOR_READ_MASK       RUBY_ECONV_NEWLINE_DECORATOR_READ_MASK  /**< @old{RUBY_ECONV_NEWLINE_DECORATOR_READ_MASK} */
#define ECONV_NEWLINE_DECORATOR_WRITE_MASK      RUBY_ECONV_NEWLINE_DECORATOR_WRITE_MASK /**< @old{RUBY_ECONV_NEWLINE_DECORATOR_WRITE_MASK} */
#define ECONV_UNIVERSAL_NEWLINE_DECORATOR       RUBY_ECONV_UNIVERSAL_NEWLINE_DECORATOR  /**< @old{RUBY_ECONV_UNIVERSAL_NEWLINE_DECORATOR} */
#define ECONV_CRLF_NEWLINE_DECORATOR            RUBY_ECONV_CRLF_NEWLINE_DECORATOR       /**< @old{RUBY_ECONV_CRLF_NEWLINE_DECORATOR} */
#define ECONV_CR_NEWLINE_DECORATOR              RUBY_ECONV_CR_NEWLINE_DECORATOR         /**< @old{RUBY_ECONV_CR_NEWLINE_DECORATOR} */
#define ECONV_XML_TEXT_DECORATOR                RUBY_ECONV_XML_TEXT_DECORATOR           /**< @old{RUBY_ECONV_XML_TEXT_DECORATOR} */
#define ECONV_XML_ATTR_CONTENT_DECORATOR        RUBY_ECONV_XML_ATTR_CONTENT_DECORATOR   /**< @old{RUBY_ECONV_XML_ATTR_CONTENT_DECORATOR} */
#define ECONV_STATEFUL_DECORATOR_MASK           RUBY_ECONV_STATEFUL_DECORATOR_MASK      /**< @old{RUBY_ECONV_STATEFUL_DECORATOR_MASK} */
#define ECONV_XML_ATTR_QUOTE_DECORATOR          RUBY_ECONV_XML_ATTR_QUOTE_DECORATOR     /**< @old{RUBY_ECONV_XML_ATTR_QUOTE_DECORATOR} */
#define ECONV_DEFAULT_NEWLINE_DECORATOR         RUBY_ECONV_DEFAULT_NEWLINE_DECORATOR    /**< @old{RUBY_ECONV_DEFAULT_NEWLINE_DECORATOR} */
    /** @} */

    /**
     * @name Flags for rb_econv_convert()
     *
     * @{
     */

    /** Indicates the input is a part of much larger one. */
    RUBY_ECONV_PARTIAL_INPUT                    = 0x00010000,

    /** Instructs the converter to stop after output. */
    RUBY_ECONV_AFTER_OUTPUT                     = 0x00020000,
#define ECONV_PARTIAL_INPUT                     RUBY_ECONV_PARTIAL_INPUT /**< @old{RUBY_ECONV_PARTIAL_INPUT} */
#define ECONV_AFTER_OUTPUT                      RUBY_ECONV_AFTER_OUTPUT  /**< @old{RUBY_ECONV_AFTER_OUTPUT} */

    RUBY_ECONV_FLAGS_PLACEHOLDER /**< Placeholder (not used) */
};

RBIMPL_SYMBOL_EXPORT_END()

#endif /* RUBY_INTERNAL_ENCODING_TRANSCODE_H */
