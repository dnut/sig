const std = @import("std");
const DynamicBitSet = std.bit_set.DynamicBitSet;
const bincode = @import("../bincode/bincode.zig");
const testing = std.testing;
const getty_bincode = @import("../bincode/getty.zig");

var gpa_allocator = std.heap.GeneralPurposeAllocator(.{}){};
var gpa = gpa_allocator.allocator();

/// ***BitVec*** uses a u64 as it's Block
///
/// TODO: make into generic to allow for any block size
///
/// We created this for compatibility with the Rust BitVec type
/// even though `DynamicBitSet` functions the same but bincode
/// serializes/deserializes differently thus why we need this
/// intermediary type.
pub const BitVec = struct {
    bits: ?[]u64,
    len: u64,

    const Self = @This();

    pub fn initFromBitSet(bitset: DynamicBitSet) Self {
        if (bitset.capacity() > 0) {
            return Self{
                .bits = bitset.unmanaged.masks[0..(bitset.unmanaged.bit_length / 64)],
                .len = @as(u64, bitset.unmanaged.bit_length),
            };
        }
        return Self{
            .bits = null,
            .len = @as(u64, bitset.unmanaged.bit_length),
        };
    }

    pub fn toBitSet(self: *const Self, allocator: std.mem.Allocator) !DynamicBitSet {
        var bitset = try DynamicBitSet.initEmpty(allocator, self.len);
        errdefer bitset.deinit();

        if (self.bits) |bits| {
            for (0..(self.len / 64)) |i| {
                bitset.unmanaged.masks[i] = bits[i];
            }
        }
        return bitset;
    }
};

test "bloom.bitvec: serializes/deserializes and matches Rust's BitVec" {
    var rust_bit_vec_serialized = [_]u8{
        1,   2,   0,   0,   0,   0,   0, 0, 0, 255, 255, 239, 191, 255, 255, 255, 255, 255, 255, 255,
        255, 255, 255, 255, 255, 128, 0, 0, 0, 0,   0,   0,   0,
    };
    var bitset = try DynamicBitSet.initFull(testing.allocator, 128);

    bitset.setValue(20, false);
    bitset.setValue(30, false);
    defer bitset.deinit();

    // buf needs to be at least :
    //   4 (32 bits enum for option)
    //   n (size * 8 (64 bits for u64 block sizes))
    //   8 + (len of slice above)
    // + 8 (u64 for len field)
    // -------------------------
    //   z <- size of buf

    var buf: [10000]u8 = undefined;

    const original = BitVec.initFromBitSet(bitset);
    var out = try getty_bincode.writeToSlice(buf[0..], original, getty_bincode.Params.standard);

    var deserialied = try getty_bincode.readFromSlice(testing.allocator, BitVec, out, getty_bincode.Params.standard);
    defer getty_bincode.free(testing.allocator, deserialied);

    try testing.expect(std.mem.eql(u64, original.bits.?[0..], deserialied.bits.?[0..]));
    try testing.expectEqualSlices(u8, rust_bit_vec_serialized[0..], out[0..]);
}
