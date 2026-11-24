// SPDX-FileCopyrightText: 2026 Darling Developers
// SPDX-License-Identifier: MPL-2.0

// Function constants ([[function_constant(n)]]) of a library made from MSL source: a function lists the
// constants it reads in functionConstantsDictionary, and the values given to
// -newFunctionWithName:constantValues:error:, by index or by name, are what its pipelines read;
// is_function_constant_defined says which were given. A value of another type than its constant is an
// error. Exits 77 when there is no Metal device.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSString* const source =
	@"#include <metal_stdlib>\nusing namespace metal;\n"
	"constant bool flag [[function_constant(0)]];\n"
	"constant int offset [[function_constant(1)]];\n"
	"constant uint mask [[function_constant(2)]];\n"
	"constant float scale [[function_constant(3)]];\n"
	"constant int optional_value [[function_constant(4)]];\n"
	"constant int unread [[function_constant(5)]];\n"
	"constant bool has_optional = is_function_constant_defined(optional_value);\n"
	"uint scaled(uint x) { return uint(float(x) * scale); }\n"
	"kernel void fc(device uint* out [[buffer(0)]]) {\n"
	"	out[0] = flag ? 1 : 0;\n"
	"	out[1] = uint(offset);\n"
	"	out[2] = mask;\n"
	"	out[3] = scaled(10);\n"
	"	out[4] = has_optional ? uint(optional_value) : 0xdeadbeef;\n"
	"	out[5] = is_function_constant_defined(mask) ? 1 : 0;\n"
	"}\n"
	"kernel void plain(device uint* out [[buffer(0)]]) {\n"
	"	out[0] = 7;\n"
	"}\n";

enum { count = 6 };

// Runs `function` once and copies its output to `out`; NO when no pipeline can be made of it.
static BOOL run(id<MTLDevice> device, id<MTLFunction> function, uint32_t* out) {
	NSError* error = nil;
	id<MTLComputePipelineState> pipeline = [device newComputePipelineStateWithFunction: function error: &error];
	if (pipeline == nil) {
		printf("pipeline: %s\n", error.description.UTF8String);
		return NO;
	}
	id<MTLCommandQueue> queue = [device newCommandQueue];
	id<MTLBuffer> buffer = [device newBufferWithLength: count * sizeof(uint32_t) options: MTLResourceStorageModeShared];
	memset(buffer.contents, 0, count * sizeof(uint32_t));
	id<MTLCommandBuffer> commands = [queue commandBuffer];
	id<MTLComputeCommandEncoder> encoder = [commands computeCommandEncoder];
	[encoder setComputePipelineState: pipeline];
	[encoder setBuffer: buffer offset: 0 atIndex: 0];
	[encoder dispatchThreadgroups: MTLSizeMake(1, 1, 1) threadsPerThreadgroup: MTLSizeMake(1, 1, 1)];
	[encoder endEncoding];
	[commands commit];
	[commands waitUntilCompleted];
	memcpy(out, buffer.contents, count * sizeof(uint32_t));
	[buffer release];
	[pipeline release];
	[queue release];
	return YES;
}

int main(void) {
	@autoreleasepool {
		id<MTLDevice> device = MTLCreateSystemDefaultDevice();
		if (device == nil) {
			printf("SKIP: no Metal device\n");
			return 77;
		}

		NSError* error = nil;
		id<MTLLibrary> library = [device newLibraryWithSource: source options: nil error: &error];
		CHECK(library != nil);
		if (library == nil) {
			printf("library: %s\n", error.description.UTF8String);
			printf("FAILED: %d\n", failures);
			return 1;
		}

		// the constants each function reads, and only those
		id<MTLFunction> fc = [library newFunctionWithName: @"fc"];
		NSDictionary<NSString*, MTLFunctionConstant*>* constants = fc.functionConstantsDictionary;
		CHECK(constants.count == 5);
		CHECK(constants[@"flag"].type == MTLDataTypeBool && constants[@"flag"].index == 0);
		CHECK(constants[@"offset"].type == MTLDataTypeInt && constants[@"offset"].index == 1);
		CHECK(constants[@"mask"].type == MTLDataTypeUInt && constants[@"mask"].index == 2);
		CHECK(constants[@"scale"].type == MTLDataTypeFloat && constants[@"scale"].index == 3);
		CHECK(constants[@"optional_value"].type == MTLDataTypeInt && constants[@"optional_value"].index == 4);
		CHECK(constants[@"unread"] == nil);
		id<MTLFunction> plain = [library newFunctionWithName: @"plain"];
		CHECK(plain != nil && plain.functionConstantsDictionary.count == 0);

		// values by index, and one by name
		MTLFunctionConstantValues* values = [[MTLFunctionConstantValues alloc] init];
		bool flag = true;
		int offset = -5;
		uint32_t mask = 0x80000001u;
		float scale = 2.5f;
		[values setConstantValue: &flag type: MTLDataTypeBool atIndex: 0];
		[values setConstantValue: &offset type: MTLDataTypeInt atIndex: 1];
		[values setConstantValue: &mask type: MTLDataTypeUInt withName: @"mask"];
		[values setConstantValue: &scale type: MTLDataTypeFloat atIndex: 3];
		id<MTLFunction> specialized = [library newFunctionWithName: @"fc" constantValues: values error: &error];
		CHECK(specialized != nil);
		uint32_t out[count];
		CHECK(specialized != nil && run(device, specialized, out));
		if (specialized != nil) {
			CHECK(out[0] == 1);
			CHECK(out[1] == (uint32_t)-5);
			CHECK(out[2] == 0x80000001u);
			CHECK(out[3] == 25);
			// optional_value has no value, so it is not defined
			CHECK(out[4] == 0xdeadbeef);
			CHECK(out[5] == 1);
		}

		// with optional_value given and the others changed
		int optionalValue = 42;
		flag = false;
		scale = 0.5f;
		[values setConstantValue: &optionalValue type: MTLDataTypeInt atIndex: 4];
		[values setConstantValue: &flag type: MTLDataTypeBool atIndex: 0];
		[values setConstantValue: &scale type: MTLDataTypeFloat atIndex: 3];
		id<MTLFunction> other = [library newFunctionWithName: @"fc" constantValues: values error: &error];
		CHECK(other != nil && run(device, other, out));
		if (other != nil) {
			CHECK(out[0] == 0);
			CHECK(out[3] == 5);
			CHECK(out[4] == 42);
		}

		// a value of another type than its constant
		MTLFunctionConstantValues* wrong = [[MTLFunctionConstantValues alloc] init];
		[wrong setConstantValue: &scale type: MTLDataTypeFloat atIndex: 1];
		error = nil;
		CHECK([library newFunctionWithName: @"fc" constantValues: wrong error: &error] == nil);
		CHECK([error.domain isEqualToString: MTLLibraryErrorDomain] && error.code == MTLLibraryErrorCompileFailure);

		[wrong release];
		[values release];
		[other release];
		[specialized release];
		[plain release];
		[fc release];
		[library release];
		[device release];
	}
	printf(failures ? "FAILED: %d\n" : "OK\n", failures);
	return failures != 0;
}
