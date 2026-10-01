#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

int main(void) {
  @autoreleasepool {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) return 77;

    // A unique function name prevents a cached library from hiding a compilation failure.
    NSString *name = [@"sandbox_" stringByAppendingString:
      [NSUUID.UUID.UUIDString stringByReplacingOccurrencesOfString:@"-" withString:@""]];
    NSString *source = [NSString stringWithFormat:@"#include <metal_stdlib>\nkernel void %@() {}", name];
    NSError *error = nil;
    id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
    if (!library) {
      fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
      return 1;
    }
    return [library newFunctionWithName:name] ? 0 : 1;
  }
}
