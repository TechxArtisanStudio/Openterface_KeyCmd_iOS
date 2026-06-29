import Foundation

/// Thread-safe byte pipe using AsyncStream.
/// Replaces Java's PipedInputStream/PipedOutputStream which fails when the
/// writing thread exits (SSH handshake uses a transient connect thread).
///
/// Usage:
/// ```swift
/// let pipe = QueuePipe(capacity: 256)
///
/// // Writer (any thread)
/// pipe.writer.write(data)
/// pipe.writer.close()  // signals EOF
///
/// // Reader (any thread)
/// while let chunk = await pipe.reader.read() {
///     // process chunk
/// }
/// ```
final class QueuePipe {

    // MARK: - Reader

    /// Reader end of the pipe.
    final class Reader {
        private var iterator: AsyncStream<Data?>.Iterator
        private var closed = false

        init(stream: AsyncStream<Data?>) {
            self.iterator = stream.makeAsyncIterator()
        }

        /// Read next chunk of data. Returns nil on EOF.
        func read() async -> Data? {
            guard !closed else { return nil }
            let next = await iterator.next()
            return next ?? nil
        }

        /// Close the reader, discarding any buffered data.
        func close() {
            closed = true
        }
    }

    // MARK: - Writer

    /// Writer end of the pipe.
    final class Writer {
        private let continuation: AsyncStream<Data?>.Continuation
        private var closed = false

        init(continuation: AsyncStream<Data?>.Continuation) {
            self.continuation = continuation
        }

        /// Write a chunk of data. Rejects zero-length writes.
        func write(_ data: Data) {
            guard !data.isEmpty, !closed else { return }
            continuation.yield(data)
        }

        /// Signal end-of-stream.
        func close() {
            guard !closed else { return }
            closed = true
            continuation.yield(nil)  // EOF sentinel
            continuation.finish()
        }
    }

    // MARK: - Public properties

    /// The reader end of the pipe.
    let input: Reader

    /// The writer end of the pipe.
    let output: Writer

    // MARK: - Init

    init(capacity: Int = 256) {
        var continuationRef: AsyncStream<Data?>.Continuation!
        let stream = AsyncStream<Data?>(bufferingPolicy: .bufferingNewest(capacity)) { cont in
            continuationRef = cont
        }
        self.input = Reader(stream: stream)
        self.output = Writer(continuation: continuationRef)
    }

    /// Close both ends of the pipe.
    func close() {
        output.close()
        input.close()
    }
}