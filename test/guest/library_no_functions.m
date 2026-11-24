// SPDX-FileCopyrightText: 2026 Darling Developers
// SPDX-License-Identifier: MPL-2.0

// newLibraryWithSource: of a source with no kernel, vertex or fragment function (an empty string, only
// declarations, only a helper function) makes a library with no functions; an error in such a source is
// still an error. Exits 77 when there is no Metal device.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

int main(void) {
	@autoreleasepool {
		id<MTLDevice> device = [MTLCreateSystemDefaultDevice() autorelease];
		if (device == nil) {
			printf("SKIP: no Metal device\n");
			return 77;
		}

		NSArray<NSString*>* sources = @[
			@"",
			@"#include <metal_stdlib>\nusing namespace metal;\n",
			@"struct Unused { float a; };\n",
			@"float twice(float x) { return x * 2.0f; }\n",
		];
		for (NSString* source in sources) {
			NSError* error = nil;
			id<MTLLibrary> library = [[device newLibraryWithSource: source options: nil error: &error] autorelease];
			CHECK(library != nil && error == nil);
			if (library == nil) {
				printf("library of \"%s\": %s\n", source.UTF8String, error.description.UTF8String);
				continue;
			}
			CHECK(library.functionNames.count == 0);
			CHECK([library newFunctionWithName: @"twice"] == nil);
		}

		NSError* error = nil;
		CHECK([device newLibraryWithSource: @"float twice(float x) { return x * undeclared; }\n" options: nil error: &error] == nil);
		CHECK([error.domain isEqualToString: MTLLibraryErrorDomain] && error.code == MTLLibraryErrorCompileFailure);
	}
	printf(failures ? "FAILED: %d\n" : "OK\n", failures);
	return failures != 0;
}
