// SPDX-FileCopyrightText: 2026 Darling Developers
// SPDX-License-Identifier: MPL-2.0

// Function constants of every scalar type (bool, char, uchar, short, ushort, int, uint, long, ulong, half and
// float), in a library made from MSL source: functionConstantsDictionary reports each one's type, and the
// value given to -newFunctionWithName:constantValues:error: is what the kernel reads, all 64 bits of a long
// and a ulong. A binary archive holds a function with its values: one ulong value is not another with the
// same low 32 bits. Exits 77 when there is no Metal device.
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static int failures;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); failures++; } } while (0)

static NSString* const source =
	@"#include <metal_stdlib>\nusing namespace metal;\n"
	"constant bool cb [[function_constant(0)]];\n"
	"constant char cc [[function_constant(1)]];\n"
	"constant uchar cuc [[function_constant(2)]];\n"
	"constant short cs [[function_constant(3)]];\n"
	"constant ushort cus [[function_constant(4)]];\n"
	"constant int ci [[function_constant(5)]];\n"
	"constant uint cu [[function_constant(6)]];\n"
	"constant long cl [[function_constant(7)]];\n"
	"constant ulong cul [[function_constant(8)]];\n"
	"constant half ch [[function_constant(9)]];\n"
	"constant float cf [[function_constant(10)]];\n"
	"kernel void types(device ulong* out [[buffer(0)]]) {\n"
	"	out[0] = cb ? 1 : 0;\n"
	"	out[1] = ulong(cc);\n"
	"	out[2] = cuc;\n"
	"	out[3] = ulong(cs);\n"
	"	out[4] = cus;\n"
	"	out[5] = ulong(ci);\n"
	"	out[6] = cu;\n"
	"	out[7] = ulong(cl);\n"
	"	out[8] = cul;\n"
	"	out[9] = ulong(float(ch) * 4.0f);\n"
	"	out[10] = ulong(cf * 4.0f);\n"
	"}\n";

enum { count = 11 };

static BOOL run(id<MTLDevice> device, id<MTLFunction> function, uint64_t* out) {
	NSError* error = nil;
	id<MTLComputePipelineState> pipeline = [[device newComputePipelineStateWithFunction: function error: &error] autorelease];
	if (pipeline == nil) {
		printf("pipeline: %s\n", error.description.UTF8String);
		return NO;
	}
	id<MTLCommandQueue> queue = [[device newCommandQueue] autorelease];
	id<MTLBuffer> buffer = [[device newBufferWithLength: count * sizeof(uint64_t) options: MTLResourceStorageModeShared] autorelease];
	memset(buffer.contents, 0, count * sizeof(uint64_t));
	id<MTLCommandBuffer> commands = [queue commandBuffer];
	id<MTLComputeCommandEncoder> encoder = [commands computeCommandEncoder];
	[encoder setComputePipelineState: pipeline];
	[encoder setBuffer: buffer offset: 0 atIndex: 0];
	[encoder dispatchThreadgroups: MTLSizeMake(1, 1, 1) threadsPerThreadgroup: MTLSizeMake(1, 1, 1)];
	[encoder endEncoding];
	[commands commit];
	[commands waitUntilCompleted];
	memcpy(out, buffer.contents, count * sizeof(uint64_t));
	return YES;
}

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

		id<MTLFunction> plain = [[library newFunctionWithName: @"types"] autorelease];
		NSDictionary<NSString*, MTLFunctionConstant*>* constants = plain.functionConstantsDictionary;
		const MTLDataType types[count] = { MTLDataTypeBool, MTLDataTypeChar, MTLDataTypeUChar, MTLDataTypeShort,
			MTLDataTypeUShort, MTLDataTypeInt, MTLDataTypeUInt, MTLDataTypeLong, MTLDataTypeULong, MTLDataTypeHalf,
			MTLDataTypeFloat };
		NSArray* names = @[ @"cb", @"cc", @"cuc", @"cs", @"cus", @"ci", @"cu", @"cl", @"cul", @"ch", @"cf" ];
		CHECK(constants.count == count);
		for (NSUInteger i = 0; i < count; i++) {
			MTLFunctionConstant* constant = constants[names[i]];
			CHECK(constant != nil && constant.type == types[i] && constant.index == i);
		}

		bool b = true;
		int8_t c = -3;
		uint8_t uc = 200;
		int16_t s = -7;
		uint16_t us = 65000;
		int32_t i = -5;
		uint32_t u = 0xdeadbeef;
		int64_t l = -123456789012345;
		uint64_t ul = 0x1122334455667788;
		__fp16 h = 2.5;
		float f = 1.5f;
		MTLFunctionConstantValues* values = [[[MTLFunctionConstantValues alloc] init] autorelease];
		[values setConstantValue: &b type: MTLDataTypeBool atIndex: 0];
		[values setConstantValue: &c type: MTLDataTypeChar atIndex: 1];
		[values setConstantValue: &uc type: MTLDataTypeUChar atIndex: 2];
		[values setConstantValue: &s type: MTLDataTypeShort atIndex: 3];
		[values setConstantValue: &us type: MTLDataTypeUShort atIndex: 4];
		[values setConstantValue: &i type: MTLDataTypeInt atIndex: 5];
		[values setConstantValue: &u type: MTLDataTypeUInt atIndex: 6];
		[values setConstantValue: &l type: MTLDataTypeLong atIndex: 7];
		[values setConstantValue: &ul type: MTLDataTypeULong withName: @"cul"];
		[values setConstantValue: &h type: MTLDataTypeHalf atIndex: 9];
		[values setConstantValue: &f type: MTLDataTypeFloat atIndex: 10];
		id<MTLFunction> function = [[library newFunctionWithName: @"types" constantValues: values error: &error] autorelease];
		uint64_t out[count];
		CHECK(function != nil && run(device, function, out));
		if (function != nil) {
			CHECK(out[0] == 1);
			CHECK(out[1] == (uint64_t)-3);
			CHECK(out[2] == 200);
			CHECK(out[3] == (uint64_t)-7);
			CHECK(out[4] == 65000);
			CHECK(out[5] == (uint64_t)-5);
			CHECK(out[6] == 0xdeadbeef);
			CHECK(out[7] == (uint64_t)-123456789012345);
			CHECK(out[8] == 0x1122334455667788);
			CHECK(out[9] == 10);
			CHECK(out[10] == 6);
		}

		// a value of another type, or of another size, than its constant
		MTLFunctionConstantValues* wrong = [[[MTLFunctionConstantValues alloc] init] autorelease];
		[wrong setConstantValue: &l type: MTLDataTypeLong atIndex: 8];
		error = nil;
		CHECK([library newFunctionWithName: @"types" constantValues: wrong error: &error] == nil);
		CHECK([error.domain isEqualToString: MTLLibraryErrorDomain] && error.code == MTLLibraryErrorCompileFailure);

		// a binary archive tells a ulong from another one with the same low 32 bits
		MTLBinaryArchiveDescriptor* archiveDescriptor = [[MTLBinaryArchiveDescriptor new] autorelease];
		id<MTLBinaryArchive> archive = [[device newBinaryArchiveWithDescriptor: archiveDescriptor error: &error] autorelease];
		MTLComputePipelineDescriptor* descriptor = [[MTLComputePipelineDescriptor new] autorelease];
		descriptor.computeFunction = function;
		CHECK(archive != nil && [archive addComputePipelineFunctionsWithDescriptor: descriptor error: &error]);
		descriptor.binaryArchives = @[ archive ];
		CHECK([[device newComputePipelineStateWithDescriptor: descriptor options: MTLPipelineOptionFailOnBinaryArchiveMiss
		                                          reflection: nil error: &error] autorelease] != nil);
		uint64_t other = 0xffeeddcc55667788;
		[values setConstantValue: &other type: MTLDataTypeULong atIndex: 8];
		id<MTLFunction> otherFunction = [[library newFunctionWithName: @"types" constantValues: values error: &error] autorelease];
		CHECK(otherFunction != nil && run(device, otherFunction, out) && out[8] == 0xffeeddcc55667788);
		descriptor.computeFunction = otherFunction;
		error = nil;
		CHECK([[device newComputePipelineStateWithDescriptor: descriptor options: MTLPipelineOptionFailOnBinaryArchiveMiss
		                                          reflection: nil error: &error] autorelease] == nil);
	}
	printf(failures ? "FAILED: %d\n" : "OK\n", failures);
	return failures != 0;
}
