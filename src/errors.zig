pub const out_of_memory = "Program ran out of memory!";

pub const FileFormatError = error {
    InvalidFileHeader,
    InvalidDIBHeader,
    UnsupportedFormat,
    UnsupportedCompressionMethod,
    MalformedChunk,
    MissingField,
    CorruptedData,
    InvalidHuffmanCode,
    FileNotFound,
    UnknownError
};
