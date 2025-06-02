#ifndef ONIGURUMA_REGEX_H                            /*-*-C++-*-vi:se ft=cpp:*/
#define ONIGURUMA_REGEX_H 1
/**
 * @author     $Author$
 * @copyright  Copyright (C) 1993-2007 Yukihiro Matsumoto
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 */
#if defined(__cplusplus)
extern "C" {
#if 0
} /* satisfy cc-mode */
#endif
#endif

#ifdef RUBY
#include "ruby/oniguruma.h"
#else
#include "oniguruma.h"
#endif

RUBY_SYMBOL_EXPORT_BEGIN

#ifndef ONIG_RUBY_M17N

ONIG_EXTERN OnigEncoding    OnigEncDefaultCharEncoding;

#define mbclen(p,e,enc)  rb_enc_mbclen((p),(e),(enc))

#endif /* ifndef ONIG_RUBY_M17N */

RUBY_SYMBOL_EXPORT_END

#if defined(__cplusplus)
#if 0
{ /* satisfy cc-mode */
#endif
}  /* extern "C" { */
#endif

#endif /* ONIGURUMA_REGEX_H */
