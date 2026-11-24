// SPDX-FileCopyrightText: 2026 Darling Developers
// SPDX-License-Identifier: MPL-2.0

// MTLLibrary.functionNames lists the functions a library made from MSL source has: its kernel, vertex and
// fragment functions, and no helper; a library with none lists none. Exits 77 when there is no Metal device.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSString* const source =
	@"#include <metal_stdlib>\nusing namespace metal;\n"
	"float twice(float x) { return x * 2.0f; }\n"
	"kernel void scale(device float* data [[buffer(0)]], uint i [[thread_position_in_grid]]) {\n"
	"	data[i] = twice(data[i]);\n}\n"
	"kernel void clear(device float* data [[buffer(0)]], uint i [[thread_position_in_grid]]) {\n"
	"	data[i] = 0.0f;\n}\n"
	"vertex float4 corner(uint vid [[vertex_id]]) {\n"
	"	return float4(float(vid & 1), float(vid >> 1), 0.0, 1.0);\n}\n"
	"fragment float4 red() {\n"
	"	return float4(1.0, 0.0, 0.0, 1.0);\n}\n";

int main(void) {
	@autoreleasepool {
		id<MTLDevice> device = [MTLCreateSystemDefaultDevice() autorelease];
		if (device == nil) {
			printf("SKIP: no Metal device\n");
			return 77;
		}

		NSError* error = nil;
		id<MTLLibrary> library = [[device newLibraryWithSource: source options: nil error: &error] autorelease];
		CHECK(library != nil);
		if (library == nil) {
			printf("library: %s\n", error.description.UTF8String);
			printf("FAILED: %d\n", failures);
			return 1;
		}

		NSArray<NSString*>* names = library.functionNames;
		CHECK(names != nil);
		CHECK([[names sortedArrayUsingSelector: @selector(compare:)] isEqualToArray: (@[ @"clear", @"corner", @"red", @"scale" ])]);
		for (NSString* name in names) {
			CHECK([[library newFunctionWithName: name] autorelease] != nil);
		}

		// a library with no functions lists none, in an empty array
		id<MTLLibrary> empty = [[device newLibraryWithSource: @"float twice(float x) { return x * 2.0f; }\n" options: nil error: &error] autorelease];
		CHECK(empty != nil && empty.functionNames != nil && empty.functionNames.count == 0);
	}
	printf(failures ? "FAILED: %d\n" : "OK\n", failures);
	return failures != 0;
}
