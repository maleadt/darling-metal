// SPDX-FileCopyrightText: 2026 Darling Developers
// SPDX-License-Identifier: MPL-2.0

#import <Metal/MTLLibraryInternal.h>
#import <Metal/MTLFunctionDescriptor.h>
#import <Metal/MTLDevice.h>
#import <Metal/stubs.h>
#import <Metal/MTLIndiumErrors.h>
#import <Metal/MTLAttributeInfo.h>
#include <algorithm>
#include <cstring>

#if DARLING_METAL_ENABLED
#include <CommonCrypto/CommonDigest.h>
#endif

MTL_EXTERN NSErrorDomain const MTLLibraryErrorDomain = @"MTLLibraryErrorDomain";

#if DARLING_METAL_ENABLED
// The data type of a function constant of each Indium type, and the size of its value.
static MTLDataType MTLDataTypeOfFunctionConstant(Indium::FunctionConstantType type, size_t* size = nullptr)
{
	MTLDataType dataType = MTLDataTypeNone;
	size_t bytes = 0;
	switch (type) {
		case Indium::FunctionConstantType::Bool: dataType = MTLDataTypeBool; bytes = 1; break;
		case Indium::FunctionConstantType::Int: dataType = MTLDataTypeInt; bytes = 4; break;
		case Indium::FunctionConstantType::UInt: dataType = MTLDataTypeUInt; bytes = 4; break;
		case Indium::FunctionConstantType::Float: dataType = MTLDataTypeFloat; bytes = 4; break;
		case Indium::FunctionConstantType::Char: dataType = MTLDataTypeChar; bytes = 1; break;
		case Indium::FunctionConstantType::UChar: dataType = MTLDataTypeUChar; bytes = 1; break;
		case Indium::FunctionConstantType::Short: dataType = MTLDataTypeShort; bytes = 2; break;
		case Indium::FunctionConstantType::UShort: dataType = MTLDataTypeUShort; bytes = 2; break;
		case Indium::FunctionConstantType::Half: dataType = MTLDataTypeHalf; bytes = 2; break;
		case Indium::FunctionConstantType::Long: dataType = MTLDataTypeLong; bytes = 8; break;
		case Indium::FunctionConstantType::ULong: dataType = MTLDataTypeULong; bytes = 8; break;
	}
	if (size) {
		*size = bytes;
	}
	return dataType;
}
#endif

@interface MTLFunctionConstant ()
- (instancetype)initWithName: (NSString*)name type: (MTLDataType)type index: (NSUInteger)index;
@end

@implementation MTLFunctionConstant

@synthesize name = _name;
@synthesize type = _type;
@synthesize index = _index;

- (instancetype)initWithName: (NSString*)name type: (MTLDataType)type index: (NSUInteger)index
{
	self = [super init];
	if (self != nil) {
		_name = [name copy];
		_type = type;
		_index = index;
	}
	return self;
}

- (void)dealloc
{
	[_name release];
	[super dealloc];
}

- (BOOL)required
{
	return YES;
}

@end


// MTLVertexAttribute and MTLAttribute carry the same four facts. Their instances are only made for a
// function's reflection.
@interface MTLVertexAttribute ()
- (instancetype)initWithName: (NSString*)name index: (NSUInteger)index type: (MTLDataType)type;
@end

@interface MTLAttribute ()
- (instancetype)initWithName: (NSString*)name index: (NSUInteger)index type: (MTLDataType)type;
@end

@implementation MTLVertexAttribute

@synthesize name = _name;
@synthesize attributeIndex = _attributeIndex;
@synthesize attributeType = _attributeType;

- (instancetype)initWithName: (NSString*)name index: (NSUInteger)index type: (MTLDataType)type
{
	self = [super init];
	if (self != nil) {
		_name = [name copy];
		_attributeIndex = index;
		_attributeType = type;
	}
	return self;
}

- (void)dealloc
{
	[_name release];
	[super dealloc];
}

- (BOOL)isActive
{
	return YES;
}

- (BOOL)isPatchData
{
	return NO;
}

- (BOOL)isPatchControlPointData
{
	return NO;
}

@end

@implementation MTLAttribute

@synthesize name = _name;
@synthesize attributeIndex = _attributeIndex;
@synthesize attributeType = _attributeType;

- (instancetype)initWithName: (NSString*)name index: (NSUInteger)index type: (MTLDataType)type
{
	self = [super init];
	if (self != nil) {
		_name = [name copy];
		_attributeIndex = index;
		_attributeType = type;
	}
	return self;
}

- (void)dealloc
{
	[_name release];
	[super dealloc];
}

- (BOOL)isActive
{
	return YES;
}

- (BOOL)isPatchData
{
	return NO;
}

- (BOOL)isPatchControlPointData
{
	return NO;
}

@end

@implementation MTLFunctionInternal

#if DARLING_METAL_ENABLED

@synthesize function = _function;
@synthesize archiveKey = _archiveKey;
@synthesize device = _device;
@synthesize functionType = _functionType;
@synthesize name = _name;
@synthesize options = _options;
@synthesize patchType = _patchType;
@synthesize patchControlPointCount = _patchControlPointCount;
@synthesize vertexAttributes = _vertexAttributes;
@synthesize stageInputAttributes = _stageInputAttributes;
@synthesize functionConstantsDictionary = _functionConstantsDictionary;
@synthesize label = _label;

- (instancetype)initWithFunction: (std::shared_ptr<Indium::Function>)function
                          device: (id<MTLDevice>)device
                      archiveKey: (NSData*)archiveKey
{
	self = [super init];
	if (self != nil) {
		_function = function;
		_device = [device retain];
		_archiveKey = [archiveKey copy];

		// cache the name
		_name = [[NSString alloc] initWithUTF8String: _function->name().c_str()];
		// Indium's FunctionType values are Metal's
		_functionType = static_cast<MTLFunctionType>(_function->functionType());

		NSMutableDictionary<NSString*, MTLFunctionConstant*>* constants = [NSMutableDictionary dictionary];
		for (const auto& constant: _function->functionConstants()) {
			MTLDataType type = MTLDataTypeOfFunctionConstant(constant.type);
			NSString* constantName = [NSString stringWithUTF8String: constant.name.c_str()];
			MTLFunctionConstant* object = [[MTLFunctionConstant alloc] initWithName: constantName type: type index: constant.index];
			constants[constantName] = object;
			[object release];
		}
		_functionConstantsDictionary = [constants copy];

		// a vertex function's [[stage_in]] attributes; the other stages' inputs are not reflected
		if (_functionType == MTLFunctionTypeVertex) {
			NSMutableArray<MTLVertexAttribute*>* vertexAttributes = [NSMutableArray array];
			NSMutableArray<MTLAttribute*>* stageInputAttributes = [NSMutableArray array];
			for (const auto& info: _function->argumentInfo()) {
				if (info.kind != Indium::ArgumentKind::VertexInput) {
					continue;
				}
				NSString* attributeName = [NSString stringWithUTF8String: info.name.c_str()] ?: @"";
				MTLDataType type = static_cast<MTLDataType>(MTLAttributeInfo::dataTypeFromName(info.typeName));
				MTLVertexAttribute* vertexAttribute = [[MTLVertexAttribute alloc] initWithName: attributeName index: info.index type: type];
				MTLAttribute* stageInputAttribute = [[MTLAttribute alloc] initWithName: attributeName index: info.index type: type];
				[vertexAttributes addObject: vertexAttribute];
				[stageInputAttributes addObject: stageInputAttribute];
				[vertexAttribute release];
				[stageInputAttribute release];
			}
			_vertexAttributes = [vertexAttributes copy];
			_stageInputAttributes = [stageInputAttributes copy];
		}
	}
	return self;
}

- (void)setName: (NSString*)name
{
	NSString* old = _name;
	_name = [name copy];
	[old release];
}

- (void)setOptions: (MTLFunctionOptions)options
{
	_options = options;
}

- (void)dealloc
{
	[_device release];
	[_archiveKey release];
	[_name release];
	[_vertexAttributes release];
	[_stageInputAttributes release];
	[_functionConstantsDictionary release];
	[_label release];
	[super dealloc];
}

- (id<MTLArgumentEncoder>)newArgumentEncoderWithBufferIndex: (NSUInteger)bufferIndex
{
	return [self newArgumentEncoderWithBufferIndex: bufferIndex reflection: nil];
}

- (id<MTLArgumentEncoder>)newArgumentEncoderWithBufferIndex: (NSUInteger)bufferIndex
                                                 reflection: (MTLAutoreleasedArgument*)reflection
{
	// An argument encoder is a writer: it lays arguments out in a buffer at
	// offsets and alignments the shader dictates. indium's BindingDescriptor
	// carries an argument index and a kind and nothing else - no data type, no
	// size, no alignment, no name, and an internalIndex that is a Vulkan
	// descriptor binding rather than a Metal buffer index - so any offset this
	// produced would be invented, and the shader would read the wrong bytes.
	//
	// MTLArgumentDescriptor is implemented because it only holds what the caller
	// sets. This is not, because it would have to hold an answer.
	//
	// nil is what Apple declares for this method when there is no encoder to
	// give, so a caller that checks keeps working; the log is what makes the
	// absence visible instead of leaving the caller to wonder.
	NSLog(@"MTLFunction: -newArgumentEncoderWithBufferIndex:%lu returns nil. indium does not "
		@"expose the buffer layout an argument encoder needs (its BindingDescriptor has no "
		@"dataType, size or alignment, and its internalIndex is a Vulkan descriptor binding, not "
		@"a Metal buffer index). Reading arguments through setArgumentBuffer:offset: is not "
		@"available either for the same reason.",
		(unsigned long)bufferIndex);

	return nil;
}

#else

@dynamic device;
@dynamic functionType;
@dynamic name;
@dynamic options;
@dynamic patchType;
@dynamic patchControlPointCount;
@dynamic vertexAttributes;
@dynamic stageInputAttributes;
@dynamic functionConstantsDictionary;
@dynamic label;

MTL_UNSUPPORTED_CLASS

#endif

@end

@implementation MTLLibraryInternal

#if DARLING_METAL_ENABLED

{
	std::shared_ptr<Indium::Library> _library;
	unsigned char _digest[CC_SHA256_DIGEST_LENGTH];
}

@synthesize installName = _installName;
@synthesize type = _type;
@synthesize functionNames = _functionNames;
@synthesize device = _device;
@synthesize label = _label;

- (instancetype)initWithLibrary: (std::shared_ptr<Indium::Library>)library
                         device: (id<MTLDevice>)device
                       contents: (const void*)contents
                         length: (size_t)length
{
	self = [super init];
	if (self != nil) {
		_library = library;
		CC_SHA256_CTX context;
		CC_SHA256_Init(&context);
		for (size_t offset = 0; offset < length; offset += UINT32_MAX) {
			CC_SHA256_Update(&context, static_cast<const char*>(contents) + offset, static_cast<CC_LONG>(std::min<size_t>(length - offset, UINT32_MAX)));
		}
		CC_SHA256_Final(_digest, &context);

		// TODO: dynamic libraries
		_installName = nil;
		_type = MTLLibraryTypeExecutable;

		// TODO: function names. this requires a change in Indium.
		_functionNames = nil;

		_device = [device retain];
	}
	return self;
}

- (void)dealloc
{
	[_installName release];
	[_functionNames release];
	[_device release];
	[_label release];
	[super dealloc];
}

// A function of this library, by its name and the values given for its constants, as the SHA-256 of the
// library's digest, the name and its terminating NUL, and each value (in the order of the constant indices)
// as a little-endian 64-bit index, the constant type's byte and the value's low 32 bits (all 64 for a long or
// ulong) in little-endian order.
- (NSData*)archiveKeyForFunction: (NSString*)functionName
                          values: (const Indium::FunctionConstantValues&)values
{
	CC_SHA256_CTX context;
	CC_SHA256_Init(&context);
	CC_SHA256_Update(&context, _digest, sizeof(_digest));
	const char* name = functionName.UTF8String;
	CC_SHA256_Update(&context, name, static_cast<CC_LONG>(strlen(name) + 1));
	for (const auto& [index, value]: values.byIndex()) {
		const bool wide = value.type == Indium::FunctionConstantType::Long || value.type == Indium::FunctionConstantType::ULong;
		unsigned char entry[17];
		for (int i = 0; i < 8; i++) {
			entry[i] = static_cast<unsigned char>(static_cast<uint64_t>(index) >> (8 * i));
		}
		entry[8] = static_cast<unsigned char>(value.type);
		for (int i = 0; i < (wide ? 8 : 4); i++) {
			entry[9 + i] = static_cast<unsigned char>(value.bits >> (8 * i));
		}
		CC_SHA256_Update(&context, entry, wide ? 17 : 13);
	}
	NSMutableData* key = [NSMutableData dataWithLength: CC_SHA256_DIGEST_LENGTH];
	CC_SHA256_Final(static_cast<unsigned char*>(key.mutableBytes), &context);
	return key;
}

- (id<MTLFunction>)newFunctionWithName: (NSString*)functionName
{
	if (!functionName) {
		return nil;
	}
	// this selector has no error out-parameter: a function Indium cannot create is nil
	auto func = MTLCallIndium(nullptr, MTLLibraryErrorFunctionNotFound, [&]() {
		return _library->newFunction(functionName.UTF8String);
	});
	if (!func) {
		return nil;
	}
	return [[MTLFunctionInternal alloc] initWithFunction: func device: _device archiveKey: [self archiveKeyForFunction: functionName values: {}]];
}

- (id<MTLFunction>)newFunctionWithName: (NSString*)functionName
                        constantValues: (MTLFunctionConstantValues*)constantValues
                                 error: (NSError**)error
{
	if (error) {
		*error = nil;
	}
	if (!functionName) {
		MTLSetError(error, MTLLibraryErrorFunctionNotFound, @"No function name");
		return nil;
	}

	// the function's own constants say which of the values apply to it
	auto plain = MTLCallIndium(error, MTLLibraryErrorFunctionNotFound, [&]() {
		return _library->newFunction(functionName.UTF8String);
	});
	if (!plain) {
		if (error && !*error) {
			MTLSetError(error, MTLLibraryErrorFunctionNotFound, [NSString stringWithFormat: @"Function '%@' was not found in the library", functionName]);
		}
		return nil;
	}

	Indium::FunctionConstantValues values;
	NSDictionary* byIndex = [constantValues constantsByIndex];
	NSDictionary* byName = [constantValues constantsByName];
	for (const auto& constant: plain->functionConstants()) {
		NSString* constantName = [NSString stringWithUTF8String: constant.name.c_str()];
		// a value set by index takes precedence over one set by name
		NSDictionary* entry = byIndex[@(constant.index)] ?: byName[constantName];
		if (entry == nil) {
			continue;
		}

		MTLDataType type = static_cast<MTLDataType>([entry[@"type"] unsignedIntegerValue]);
		NSData* data = entry[@"data"];
		Indium::FunctionConstantType expected = constant.type;
		size_t size = 0;
		if (type != MTLDataTypeOfFunctionConstant(expected, &size) || data.length != size) {
			MTLSetError(error, MTLLibraryErrorCompileFailure, [NSString stringWithFormat: @"The value for function constant '%@' (index %lu) does not have the constant's type", constantName, (unsigned long)constant.index]);
			return nil;
		}
		// the value as a scalar of its size, zero-extended
		uint64_t bits = 0;
		switch (data.length) {
			case sizeof(uint8_t): { uint8_t value; memcpy(&value, data.bytes, sizeof(value)); bits = value; break; }
			case sizeof(uint16_t): { uint16_t value; memcpy(&value, data.bytes, sizeof(value)); bits = value; break; }
			case sizeof(uint32_t): { uint32_t value; memcpy(&value, data.bytes, sizeof(value)); bits = value; break; }
			case sizeof(uint64_t): memcpy(&bits, data.bytes, sizeof(bits)); break;
		}
		if (expected == Indium::FunctionConstantType::Bool) {
			bits = bits != 0 ? 1 : 0;
		}
		values.setValue(constant.index, expected, bits);
	}

	std::string message;
	auto func = MTLCallIndium(error, MTLLibraryErrorCompileFailure, [&]() {
		return _library->newFunction(functionName.UTF8String, values, &message);
	});
	if (!func) {
		if (error && !*error) {
			MTLSetError(error, MTLLibraryErrorCompileFailure, [NSString stringWithUTF8String: message.c_str()]);
		}
		return nil;
	}
	return [[MTLFunctionInternal alloc] initWithFunction: func device: _device archiveKey: [self archiveKeyForFunction: functionName values: values]];
}

- (void)newFunctionWithName: (NSString*)functionName
             constantValues: (MTLFunctionConstantValues*)constantValues
          completionHandler: (void (^)(id<MTLFunction> function, NSError* error))completionHandler
{
	NSError* error = nil;
	id<MTLFunction> function = [self newFunctionWithName: functionName constantValues: constantValues error: &error];
	void (^handler)(id<MTLFunction>, NSError*) = [completionHandler copy];
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
		handler(function, error);
		[function release];
		[handler release];
	});
}

- (id<MTLFunction>)newFunctionWithDescriptor: (MTLFunctionDescriptor*)descriptor
                                       error: (NSError**)error
{
	if (error) {
		*error = nil;
	}
	NSString* functionName = descriptor.name;
	MTLFunctionInternal* function;
	if (descriptor.constantValues) {
		function = [self newFunctionWithName: functionName constantValues: descriptor.constantValues error: error];
	} else {
		function = [self newFunctionWithName: functionName];
		if (!function) {
			MTLSetError(error, MTLLibraryErrorFunctionNotFound, [NSString stringWithFormat: @"Function '%@' was not found in the library", functionName]);
		}
	}
	if (!function) {
		return nil;
	}
	if (descriptor.specializedName) {
		function.name = descriptor.specializedName;
	}
	function.options = descriptor.options;
	return function;
}

- (void)newFunctionWithDescriptor: (MTLFunctionDescriptor*)descriptor
                completionHandler: (void (^)(id<MTLFunction> function, NSError* error))completionHandler
{
	NSError* error = nil;
	id<MTLFunction> function = [self newFunctionWithDescriptor: descriptor error: &error];
	void (^handler)(id<MTLFunction>, NSError*) = [completionHandler copy];
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
		handler(function, error);
		[function release];
		[handler release];
	});
}

#else

@dynamic installName;
@dynamic type;
@dynamic functionNames;
@dynamic device;
@dynamic label;

MTL_UNSUPPORTED_CLASS

#endif

@end
