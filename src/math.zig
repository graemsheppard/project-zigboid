const std = @import("std");

pub fn Vector2(comptime T: type) type {
    return struct {
        x: T,
        y: T,

        pub fn init(x: T, y: T) Vector2(T) {
            return .{
                .x = x,
                .y = y
            };
        }
    };
}

pub fn Vector3(comptime T: type) type {
    return struct {
        x: T,
        y: T,
        z: T,

        pub fn init(x: T, y: T, z: T) Vector3(T) {
            return .{
                .x = x,
                .y = y,
                .z = z
            };
        }

        pub fn zero() Vector3(T) {
            return .{
                .x = 0,
                .y = 0,
                .z = 0
            };
        }

        pub fn one() Vector3(T) {
            return .{
                .x = 1,
                .y = 1,
                .z = 1
            };
        }
    };
}

pub fn Matrix4(comptime T: type) type {
    return struct {
        const Self = @This();
        const Row = @Vector(4, T);
        data: [4]Row,

        pub fn init(data: [4]Row)  Matrix4(T) {
            return .{
                .data = data
            };
        }

        pub fn add(a: Self, b: Self) Self {
            const r0 = a.data[0] + b.data[0];
            const r1 = a.data[1] + b.data[1];
            const r2 = a.data[2] + b.data[2];
            const r3 = a.data[3] + b.data[3];

            return Self.init(.{ r0, r1, r2, r3 });
        }

        pub fn transpose(self: Self) Self {
            const r0 = self.data[0];
            const r1 = self.data[1];
            const r2 = self.data[2];
            const r3 = self.data[3];

            return Self.init(.{
                .{ r0[0], r1[0], r2[0], r3[0] },
                .{ r0[1], r1[1], r2[1], r3[1] },
                .{ r0[2], r1[2], r2[2], r3[2] },
                .{ r0[3], r1[3], r2[3], r3[3] }
            });
        }

        pub fn multiply(a: Self, b: Self) Self {
            const r0a = a.data[0];
            const r1a = a.data[1];
            const r2a = a.data[2];
            const r3a = a.data[3];
            const bT = b.transpose();
            const c0b = bT.data[0];
            const c1b = bT.data[1];
            const c2b = bT.data[2];
            const c3b = bT.data[3];

            return Self.init(.{
                .{ dot(r0a, c0b), dot(r0a, c1b), dot(r0a, c2b), dot(r0a, c3b) },
                .{ dot(r1a, c0b), dot(r1a, c1b), dot(r1a, c2b), dot(r1a, c3b) },
                .{ dot(r2a, c0b), dot(r2a, c1b), dot(r2a, c2b), dot(r2a, c3b) },
                .{ dot(r3a, c0b), dot(r3a, c1b), dot(r3a, c2b), dot(r3a, c3b) },
            });
        }

        pub fn toArray(self: Self) [16]T {
            return @bitCast(self.data);
        }

        fn dot(a: Row, b: Row) T {
            return @reduce(.Add, a * b);
        }
    };
}
