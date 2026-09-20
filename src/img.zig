const std = @import("std");
const out_of_memory = @import("ecs.zig").out_of_memory;

pub const PNG = struct {
    file_name: []const u8,
    allocator: std.mem.Allocator,
    ihdr: IHDR,
    plte: ?PLTE,
    trns: ?TRNS,
    chunks: std.ArrayList(Chunk),
    bytes_per_row: u32,
    raw_image: []u8,


    // Parses a PNG file in the resources directory and decompresses the image data
    pub fn parse(allocator: std.mem.Allocator, io: std.Io, file_name: []const u8) FileFormatError!PNG {
        var data = try loadImage(allocator, io, file_name);
        defer allocator.free(data);

        // Validate 8-byte file signature
        if (data[0] != 0x89) return FileFormatError.InvalidFileHeader;
        const signature = std.mem.readInt(u24, data[1..4], .big);
        if (signature != 0x504E47) return FileFormatError.InvalidFileHeader;

        var chunks = std.ArrayList(Chunk).initCapacity(allocator, 3) catch return FileFormatError.InvalidFileHeader;

        // IHDR chunk must come first and have data of 13-bytes
        const ihdr_chunk = Chunk.parse(8, data);

        if (ihdr_chunk.length != 13 or !std.mem.eql(u8, ihdr_chunk.name, "IHDR"))
            return FileFormatError.MalformedChunk;

        const ihdr = try IHDR.parse(ihdr_chunk);
        const bpp = ihdr.getBitsPerPixel();
        const bytes_per_row = (bpp * ihdr.width + 7) / 8;

        const plte_required = ihdr.color_type == 3;

        var idx: usize = 33;
        var chunk_count: usize = 0;
        var plte: ?PLTE = null;
        var trns: ?TRNS = null;
        var reached_end = false;
        var bytes_to_read: usize = 0;
        while (idx < data.len) : (chunk_count += 1) {
            const chunk = Chunk.parse(idx, data);
            if (std.mem.eql(u8, chunk.name, "PLTE"))
                plte = try PLTE.parse(chunk);
            if (std.mem.eql(u8, chunk.name, "tRNS"))
                trns = try TRNS.parse(chunk);
            chunks.insert(allocator, chunk_count, chunk) catch return FileFormatError.MalformedChunk;

            // Each chunk requires at least 12 bytes for headers and CRC
            idx += chunk.length + 12;

            if (std.mem.eql(u8, chunk.name, "IDAT")) {
                bytes_to_read += chunk.data.len;
            } else if (std.mem.eql(u8, chunk.name, "IEND")) {
                reached_end = true;
                break;
            }
        }

        if (!reached_end)
            return FileFormatError.MissingField;

        if (plte_required and plte == null)
            return FileFormatError.MissingField;

        // Copy the data chunks into a contiguous array
        const compressed_data = allocator.alloc(u8, bytes_to_read) catch @panic(out_of_memory);
        defer allocator.free(compressed_data);
        var byte_offset: usize = 0;
        for (chunks.items) |chunk| {
            if (!std.mem.eql(u8, chunk.name, "IDAT")) continue;
            @memcpy(compressed_data[byte_offset..(byte_offset + chunk.data.len)], chunk.data);
            byte_offset += chunk.data.len;
        }

        const decompressed = try decompress(allocator, ihdr, bytes_per_row, compressed_data);

        return .{
            .file_name = file_name,
            .allocator = allocator,
            .ihdr = ihdr,
            .plte = plte,
            .trns = trns,
            .chunks = chunks,
            .bytes_per_row = bytes_per_row,
            .raw_image = decompressed
        };
    }

    // Helper function to load an image by file_name. Returns raw buffer holding entire file data (compressed). Caller owns the memory.
    fn loadImage(allocator: std.mem.Allocator, io: std.Io, file_name: []const u8) FileFormatError![]u8 {
        var resource_dir = std.Io.Dir.cwd().openDir(
            io,
            "resources",
            .{}
        ) catch return FileFormatError.FileNotFound;

        const data = resource_dir.readFileAlloc(
            io,
            file_name,
            allocator,
            .limited(64_000_000)
        ) catch return FileFormatError.FileNotFound;

        return data;
    }

    /// Helper function that decompresses the zlib stream, unfilters the pixels, and maps the correct colors, caller owns the allocated slice
    fn decompress(allocator: std.mem.Allocator, ihdr: IHDR, bytes_per_row: usize, data: []u8) FileFormatError![]u8 {
        // Decompress the bytes
        var buf: [std.compress.flate.max_window_len]u8 = undefined;
        var data_reader = std.Io.Reader.fixed(data);
        var decomp = std.compress.flate.Decompress.init(&data_reader, .zlib, &buf);
        var writer = std.Io.Writer.Allocating.init(allocator);
        defer writer.deinit();
        _ = decomp.reader.streamRemaining(&writer.writer) catch return FileFormatError.CorruptedData;
        const uncompressed = writer.toOwnedSlice() catch @panic(out_of_memory);
        defer allocator.free(uncompressed);

        var raw_image = allocator.alloc(u8, bytes_per_row * ihdr.height) catch return FileFormatError.CorruptedData;

        // Unfilter the data in place
        var scanline_idx: usize = 0;
        var byte_idx: usize = 0;
        var filter_method: u8 = 0;
        const scanline_size = bytes_per_row + 1;
        const bypp = (ihdr.getBitsPerPixel() + 7) / 8;
        while(scanline_idx < ihdr.height) {
            if (byte_idx == 0) {
                filter_method = uncompressed[scanline_size * scanline_idx];
                byte_idx += 1;
                continue;
            }

            if (byte_idx >= scanline_size) {
                byte_idx = 0;
                scanline_idx += 1;
                continue;
            }

            const cur_offset = scanline_idx * scanline_size + byte_idx;

            const a = if (byte_idx > bypp) uncompressed[cur_offset - bypp] else 0;
            const b = if (scanline_idx > 0) uncompressed[cur_offset - scanline_size] else 0;
            const c = if (byte_idx > bypp and scanline_idx > 0) uncompressed[cur_offset - scanline_size - bypp] else 0;

            const byte = uncompressed[cur_offset];
            uncompressed[cur_offset] = switch(filter_method) {
                0 => byte,
                1 => byte +% a,
                2 => byte +% b,
                3 => byte +% @as(u8, @truncate((@as(u16, a) + b) / 2)),
                4 => byte +% paethPredictor(a, b, c),
                else => return FileFormatError.UnsupportedFormat
            };

            byte_idx += 1;
        }

        // Handle different color types
        if (ihdr.color_type == 3) unreachable;

        // For RGB and RGBA, copy the scanlines directly without the filter byte
        if (ihdr.color_type == 2 or ihdr.color_type == 6) {
            for (0..ihdr.height) |y_idx_source| {
                const y_idx_target = ihdr.height - 1 - y_idx_source;
                const source_start_idx = y_idx_source * (bytes_per_row + 1) + 1;
                const target_start_idx = y_idx_target * bytes_per_row;
                @memcpy(raw_image[target_start_idx..(target_start_idx + bytes_per_row)], uncompressed[source_start_idx..(source_start_idx + bytes_per_row)]);
            }
        }
        
        return raw_image;
    }

    fn paethPredictor(a: u8, b: u8, c: u8) u8 {
        const ia = @as(i16, a);
        const ib = @as(i16, b);
        const ic = @as(i16, c);
        const p = ia + ib - ic;

        const pa = @abs(p - ia);
        const pb = @abs(p - ib);
        const pc = @abs(p - ic);

        if (pa <= pb and pa <= pc) return a;
        if (pb <= pc) return b;
        return c;
    }

    pub fn deinit(self: *PNG) void {
        self.chunks.deinit(self.allocator);
        self.allocator.free(self.raw_image);
    }
};

/// Stores critical information about the image and must be the first chunk (offset 8)
pub const IHDR = struct {
    width: u32,
    height: u32,
    bit_depth: u8,
    color_type: u8,
    compression_method: u8,
    filter_method: u8,
    interlace_method: u8,

    fn parse(chunk: Chunk) FileFormatError!IHDR {
        const width = std.mem.readInt(u32, chunk.data[0..4], .big);
        const height = std.mem.readInt(u32, chunk.data[4..8], .big);

        const bit_depth = chunk.data[8];
        const color_type = chunk.data[9];

        if (!isColorSpecValid(bit_depth, color_type))
            return FileFormatError.MalformedChunk;

        const compression_method = chunk.data[10];
        if (compression_method != 0)
            return FileFormatError.UnsupportedCompressionMethod;

        return .{
            .width = width,
            .height = height,
            .bit_depth = bit_depth,
            .color_type = color_type, 
            .compression_method = compression_method, 
            .filter_method = chunk.data[11],
            .interlace_method = chunk.data[12]
        };
    }

    fn getBitsPerPixel(self: IHDR) u8 {
        return switch(self.color_type) {
            0, 3 => self.bit_depth,     // Grayscale, Indexed(Palette)
            2 => self.bit_depth * 3,    // RGB
            4 => self.bit_depth * 2,    // Grayscale w/ alpha
            5 => self.bit_depth * 4,    // RGBA
            else => unreachable
        };
    }

    fn isColorSpecValid(bit_depth: u8, color_type: u8) bool {
        return switch (color_type) {
            0 => switch(bit_depth) { 1, 2, 4, 8, 16 => true, else => false },
            3 => switch(bit_depth) { 1, 2, 4, 8 => true, else => false },
            2, 4, 6 => switch(bit_depth) { 8, 16 => true, else => false },
            else => false
        };
    }
};

/// Stores the color table as a slice of 3-byte segments where each byte is R,G,B in order.
pub const PLTE = struct {
    colors: []const [3]u8,

    pub fn parse(chunk: Chunk) FileFormatError!PLTE {
        if (chunk.data.len % 3 != 0)
            return FileFormatError.MalformedChunk;

        // Retinterpret as slice of triples
        const colors = std.mem.bytesAsSlice([3]u8, chunk.data);
        
        return .{
            .colors = colors
        };
    }
};

/// Stores the alpha for each pallette index as a byte.
pub const TRNS = struct {
    alphas: []const u8,

    pub fn parse(chunk: Chunk) FileFormatError!TRNS {
        return .{
            .alphas = chunk.data
        };
    }

    /// Alphas is not guaranteed to have 256 entries so this should be used.
    pub fn alphaAt(self: TRNS, idx: usize) u8 {
        return if (idx >= self.alphas.len) 0xff else self.alphas[idx];
    }
};

const Chunk = struct {
    length: u32,
    name: []const u8,
    data: []const u8,
    crc: u32,

    pub fn parse(start_idx: usize, data: []const u8) Chunk {
        const length = std.mem.readInt(u32, data[start_idx..][0..4], .big);
        const name = data[(start_idx + 4)..(start_idx + 8)];
        const chunk_data = data[(start_idx + 8)..(start_idx + 8 + length)];
        const crc = std.mem.readInt(u32, data[(start_idx + 8 + length)..][0..4], .big);
        return .{
            .length = length,
            .name = name,
            .data = chunk_data,
            .crc = crc
        };
    }
};

pub const FileFormatError = error {
    InvalidFileHeader,
    InvalidDIBHeader,
    UnsupportedFormat,
    UnsupportedCompressionMethod,
    MalformedChunk,
    MissingField,
    CorruptedData,
    InvalidHuffmanCode,
    FileNotFound
};
