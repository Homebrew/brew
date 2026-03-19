use crate::BrewResult;
use crate::delegate;

pub(crate) fn run(args: &[String]) -> BrewResult<u8> {
    delegate::run(args)
}
