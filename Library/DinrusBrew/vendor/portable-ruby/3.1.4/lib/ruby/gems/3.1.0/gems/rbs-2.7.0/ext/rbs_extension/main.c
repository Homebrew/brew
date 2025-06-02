#include "rbs_extension.h"

void
Init_rbs_extension(void)
{
  rbs__init_constants();
  rbs__init_location();
  rbs__init_parser();
}
