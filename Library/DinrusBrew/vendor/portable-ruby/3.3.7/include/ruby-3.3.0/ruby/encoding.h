#ifndef RUBY_ENCODING_H                              /*-*-C++-*-vi:se ft=cpp:*/
#define RUBY_ENCODING_H 1
/**
 * @file
 * @author     $Author: matz $
 * @date       Thu May 24 11:49:41 JST 2007
 * @copyright  Copyright (C) 2007 Yukihiro Matsumoto
 * @copyright  This  file  is   a  part  of  the   programming  language  Ruby.
 *             Permission  is hereby  granted,  to  either redistribute  and/or
 *             modify this file, provided that  the conditions mentioned in the
 *             file COPYING are met.  Consult the file for details.
 * @brief      Encoding relates APIs.
 *
 * These APIs are mainly for  implementing encodings themselves.  Encodings are
 * built on  top of  Ruby's core  CAPIs.  Though not  prohibited, there  can be
 * relatively less rooms for things in  this header file be useful when writing
 * an extension library.
 */
#include "ruby/ruby.h"

#include "ruby/internal/encoding/coderange.h"
#include "ruby/internal/encoding/ctype.h"
#include "ruby/internal/encoding/encoding.h"
#include "ruby/internal/encoding/pathname.h"
#include "ruby/internal/encoding/re.h"
#include "ruby/internal/encoding/sprintf.h"
#include "ruby/internal/encoding/string.h"
#include "ruby/internal/encoding/symbol.h"
#include "ruby/internal/encoding/transcode.h"

#endif /* RUBY_ENCODING_H */
