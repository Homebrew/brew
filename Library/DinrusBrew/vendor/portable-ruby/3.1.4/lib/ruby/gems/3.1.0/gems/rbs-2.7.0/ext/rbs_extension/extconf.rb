require 'mkmf'
$INCFLAGS << " -I$(top_srcdir)" if $extmk
append_cflags ['-std=c99']
create_makefile 'rbs_extension'
