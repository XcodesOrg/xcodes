import Compression
import Foundation

// From: https://github.com/saagarjha/unxip
// License: GNU Lesser General Public License v3.0

extension RandomAccessCollection {
    subscript(fromOffset fromOffset: Int = 0, toOffset toOffset: Int? = nil) -> SubSequence {
        let toOffset = toOffset ?? count
        return self[index(startIndex, offsetBy: fromOffset)..<index(startIndex, offsetBy: toOffset)]
    }

    subscript(fromOffset fromOffset: Int = 0, size size: Int) -> SubSequence {
        let base = index(startIndex, offsetBy: fromOffset)
        return self[base..<index(base, offsetBy: size)]
    }
}

struct Condition {
    var stream: AsyncStream<Void>!
    var continuation: AsyncStream<Void>.Continuation!

    init() {
        stream = .init {
            continuation = $0
        }
    }

    func signal() {
        continuation.finish()
    }

    func wait() async {
        for await _ in stream {
        }
    }
}

struct Queue<Element> {
    var buffer = [Element?.none]
    var readIndex = 0 {
        didSet {
            readIndex %= buffer.count
        }
    }
    var writeIndex = 0 {
        didSet {
            writeIndex %= buffer.count
        }
    }

    var empty: Bool {
        buffer[readIndex] == nil
    }

    mutating func push(_ element: Element) {
        if readIndex == writeIndex,
            !empty
        {
            resize()
        }
        buffer[writeIndex] = element
        writeIndex += 1
    }

    mutating func pop() -> Element {
        defer {
            buffer[readIndex] = nil
            readIndex += 1
        }
        return buffer[readIndex]!
    }

    mutating func resize() {
        var buffer = [Element?](repeating: nil, count: self.buffer.count * 2)
        let slice1 = self.buffer[readIndex..<self.buffer.endIndex]
        let slice2 = self.buffer[self.buffer.startIndex..<readIndex]
        buffer[0..<slice1.count] = slice1
        buffer[slice1.count..<slice1.count + slice2.count] = slice2
        self.buffer = buffer
        readIndex = 0
        writeIndex = slice1.count + slice2.count
    }
}

protocol BackpressureProvider {
    associatedtype Element

    var loaded: Bool { get }

    mutating func enqueue(_: Element)
    mutating func dequeue(_: Element)
}

final class CountedBackpressure<Element>: BackpressureProvider {
    var count = 0
    let max: Int

    var loaded: Bool {
        count >= max
    }

    init(max: Int) {
        self.max = max
    }

    func enqueue(_: Element) {
        count += 1
    }

    func dequeue(_: Element) {
        count -= 1
    }
}

final class FileBackpressure: BackpressureProvider {
    var size = 0
    let maxSize: Int

    var loaded: Bool {
        size >= maxSize
    }

    init(maxSize: Int) {
        self.maxSize = maxSize
    }

    func enqueue(_ file: File) {
        size += file.data.map(\.count).reduce(0, +)
    }

    func dequeue(_ file: File) {
        size -= file.data.map(\.count).reduce(0, +)
    }
}

actor BackpressureStream<Element, Backpressure: BackpressureProvider>: AsyncSequence where Backpressure.Element == Element {
    struct Iterator: AsyncIteratorProtocol {
        let stream: BackpressureStream

        func next() async throws -> Element? {
            try await stream.next()
        }
    }

    // In-place mutation of an enum is not currently supported, so this avoids
    // copies of the queue when modifying the .results case on reassignment.
    // See: https://forums.swift.org/t/in-place-mutation-of-an-enum-associated-value/11747
    class QueueWrapper {
        var queue: Queue<Element> = .init()
    }

    enum Results {
        case results(QueueWrapper)
        case error(Error)
    }

    var backpressure: Backpressure
    var results = Results.results(.init())
    var finished = false
    var yieldCondition: Condition?
    var nextCondition: Condition?

    init(backpressure: Backpressure, of: Element.Type = Element.self) {
        self.backpressure = backpressure
    }

    nonisolated func makeAsyncIterator() -> Iterator {
        AsyncIterator(stream: self)
    }

    func yield(_ element: Element) async {
        assert(yieldCondition == nil)
        precondition(!backpressure.loaded)
        precondition(!finished)
        switch results {
            case .results(let results):
                results.queue.push(element)
                backpressure.enqueue(element)
                nextCondition?.signal()
                nextCondition = nil
                while backpressure.loaded {
                    yieldCondition = Condition()
                    await yieldCondition?.wait()
                }
            case .error(_):
                preconditionFailure()
        }
    }

    private func next() async throws -> Element? {
        switch results {
            case .results(let results):
                if results.queue.empty {
                    if !finished {
                        nextCondition = .init()
                        await nextCondition?.wait()
                        return try await next()
                    } else {
                        return nil
                    }
                }
                let result = results.queue.pop()
                backpressure.dequeue(result)
                yieldCondition?.signal()
                yieldCondition = nil
                return result
            case .error(let error):
                throw error
        }
    }

    nonisolated func finish() {
        Task {
            await _finish()
        }
    }

    func _finish() {
        finished = true
        nextCondition?.signal()
    }

    nonisolated func finish(throwing error: Error) {
        Task {
            await _finish(throwing: error)
        }
    }

    func _finish(throwing error: Error) {
        results = .error(error)
        nextCondition?.signal()
    }
}

actor ConcurrentStream<Element> {
    class Wrapper {
        var stream: AsyncThrowingStream<Element, Error>!
        var continuation: AsyncThrowingStream<Element, Error>.Continuation!
    }

    let wrapper = Wrapper()
    let batchSize: Int
    nonisolated var results: AsyncThrowingStream<Element, Error> {
        get {
            wrapper.stream
        }
        set {
            wrapper.stream = newValue
        }
    }
    nonisolated var continuation: AsyncThrowingStream<Element, Error>.Continuation {
        get {
            wrapper.continuation
        }
        set {
            wrapper.continuation = newValue
        }
    }
    var index = -1
    var finishedIndex = Int?.none
    var completedIndex = -1
    var widthConditions = [Int: Condition]()
    var orderingConditions = [Int: Condition]()

    init(batchSize: Int = ProcessInfo.processInfo.activeProcessorCount, consumeResults: Bool = false) {
        self.batchSize = batchSize
        results = AsyncThrowingStream<Element, Error> {
            continuation = $0
        }
        if consumeResults {
            Task {
                for try await _ in results {
                }
            }
        }
    }

    @discardableResult
    func addTask(_ operation: @escaping @Sendable () async throws -> Element) async -> Task<Element, Error> {
        index += 1
        let index = index
        let widthCondition = Condition()
        widthConditions[index] = widthCondition
        let orderingCondition = Condition()
        orderingConditions[index] = orderingCondition
        await ensureWidth(index: index)
        return Task {
            let result = await Task {
                try await operation()
            }.result
            await produce(result: result, for: index)
            return try result.get()
        }
    }

    // Unsound workaround for https://github.com/apple/swift/issues/61658
    enum BrokenBy61658 {
        @_transparent
        static func ensureWidth(_ stream: isolated ConcurrentStream, index: Int) async {
            if index >= stream.batchSize {
                await stream.widthConditions[index - stream.batchSize]!.wait()
                stream.widthConditions.removeValue(forKey: index - stream.batchSize)
            }
        }

        @_transparent
        static func produce(_ stream: isolated ConcurrentStream, result: Result<Element, Error>, for index: Int) async {
            if index != 0 {
                await stream.orderingConditions[index - 1]!.wait()
                stream.orderingConditions.removeValue(forKey: index - 1)
            }
            stream.orderingConditions[index]!.signal()
            stream.continuation.yield(with: result)
            if index == stream.finishedIndex {
                stream.continuation.finish()
            }
            stream.widthConditions[index]!.signal()
            stream.completedIndex += 1
        }
    }

    #if swift(<5.8)
        @_optimize(none)
        func ensureWidth(index: Int) async {
            await BrokenBy61658.ensureWidth(self, index: index)
        }
    #else
        func ensureWidth(index: Int) async {
            await BrokenBy61658.ensureWidth(self, index: index)
        }
    #endif

    #if swift(<5.8)
        @_optimize(none)
        func produce(result: Result<Element, Error>, for index: Int) async {
            await BrokenBy61658.produce(self, result: result, for: index)
        }
    #else
        func produce(result: Result<Element, Error>, for index: Int) async {
            await BrokenBy61658.produce(self, result: result, for: index)
        }
    #endif

    func finish() {
        finishedIndex = index
        if finishedIndex == completedIndex {
            continuation.finish()
        }
    }
}

struct DataStream<S: AsyncSequence> where S.Element: RandomAccessCollection, S.Element.Element == UInt8 {
    var position: Int = 0 {
        didSet {
            if let cap = cap {
                precondition(position <= cap)
            }
        }
    }
    var current: (S.Element.Index, S.Element)?
    var iterator: S.AsyncIterator

    var cap: Int?

    init(data: S) {
        self.iterator = data.makeAsyncIterator()
    }

    mutating func read(upTo n: Int) async throws -> [UInt8]? {
        var data = [UInt8]()
        var index = 0
        while index != n {
            let current: (S.Element.Index, S.Element)
            if let _current = self.current,
                _current.0 != _current.1.endIndex
            {
                current = _current
            } else {
                let new = try await iterator.next()
                guard let new = new else {
                    return data
                }
                current = (new.startIndex, new)
            }
            let count = min(n - index, current.1.distance(from: current.0, to: current.1.endIndex))
            let end = current.1.index(current.0, offsetBy: count)
            data.append(contentsOf: current.1[current.0..<end])
            self.current = (end, current.1)
            index += count
            position += count
        }
        return data
    }

    mutating func read(_ n: Int) async throws -> [UInt8] {
        let data = try await read(upTo: n)!
        precondition(data.count == n)
        return data
    }

    mutating func read<Integer: BinaryInteger>(_ type: Integer.Type) async throws -> Integer {
        try await read(MemoryLayout<Integer>.size).reduce(into: 0) { result, next in
            result <<= 8
            result |= Integer(next)
        }
    }
}

struct Chunk: Sendable {
    let buffer: [UInt8]

    init(data: [UInt8], decompressedSize: Int?) {
        if let decompressedSize = decompressedSize {
            let magic = [0xfd] + "7zX".utf8
            precondition(data.prefix(magic.count).elementsEqual(magic))
            buffer = [UInt8](unsafeUninitializedCapacity: decompressedSize) { buffer, count in
                precondition(compression_decode_buffer(buffer.baseAddress!, decompressedSize, data, data.count, nil, COMPRESSION_LZMA) == decompressedSize)
                count = decompressedSize
            }
        } else {
            buffer = data
        }
    }
}

struct File {
    let dev: Int
    let ino: Int
    let mode: Int
    let name: String
    var data = [ArraySlice<UInt8>]()

    struct Identifier: Hashable {
        let dev: Int
        let ino: Int
    }

    var identifier: Identifier {
        Identifier(dev: dev, ino: ino)
    }

    func compressedData() async -> [UInt8]? {
        let blockSize = 64 << 10  // LZFSE with 64K block size
        var _data = [UInt8]()
        _data.reserveCapacity(self.data.map(\.count).reduce(0, +))
        let data = self.data.reduce(into: _data, +=)
        let compressionStream = ConcurrentStream<[UInt8]?>()

        Task {
            var position = data.startIndex

            while position < data.endIndex {
                let _position = position
                await compressionStream.addTask {
                    try Task.checkCancellation()
                    let position = _position
                    let end = min(position + blockSize, data.endIndex)
                    let data = [UInt8](unsafeUninitializedCapacity: (end - position) + (end - position) / 16) { buffer, count in
                        data[position..<end].withUnsafeBufferPointer { data in
                            count = compression_encode_buffer(buffer.baseAddress!, buffer.count, data.baseAddress!, data.count, nil, COMPRESSION_LZFSE)
                            guard count < buffer.count else {
                                count = 0
                                return
                            }
                        }
                    }
                    return !data.isEmpty ? data : nil
                }
                position += blockSize
            }

            await compressionStream.finish()
        }
        var chunks = [[UInt8]]()
        do {
            for try await chunk in compressionStream.results {
                if let chunk = chunk {
                    chunks.append(chunk)
                } else {
                    return nil
                }
            }
        } catch {
            fatalError()
        }

        let tableSize = (chunks.count + 1) * MemoryLayout<UInt32>.size
        let size = tableSize + chunks.map(\.count).reduce(0, +)
        guard size < data.count else {
            return nil
        }

        return [UInt8](unsafeUninitializedCapacity: size) { buffer, count in
            var position = tableSize

            func writePosition(toTableIndex index: Int) {
                precondition(position < UInt32.max)
                for i in 0..<MemoryLayout<UInt32>.size {
                    buffer[index * MemoryLayout<UInt32>.size + i] = UInt8(position >> (i * 8) & 0xff)
                }
            }

            writePosition(toTableIndex: 0)
            for (index, chunk) in zip(1..., chunks) {
                _ = UnsafeMutableBufferPointer(rebasing: buffer.suffix(from: position)).initialize(from: chunk)
                position += chunk.count
                writePosition(toTableIndex: index)
            }
            count = size
        }
    }

    func write(compressedData data: [UInt8], toDescriptor descriptor: CInt) -> Bool {
        let uncompressedSize = self.data.map(\.count).reduce(0, +)
        let attribute =
            "cmpf".utf8.reversed()  // magic
            + [0x0c, 0x00, 0x00, 0x00]  // LZFSE, 64K chunks
            + ([
                (uncompressedSize >> 0) & 0xff,
                (uncompressedSize >> 8) & 0xff,
                (uncompressedSize >> 16) & 0xff,
                (uncompressedSize >> 24) & 0xff,
                (uncompressedSize >> 32) & 0xff,
                (uncompressedSize >> 40) & 0xff,
                (uncompressedSize >> 48) & 0xff,
                (uncompressedSize >> 56) & 0xff,
            ].map(UInt8.init) as [UInt8])

        guard fsetxattr(descriptor, "com.apple.decmpfs", attribute, attribute.count, 0, XATTR_SHOWCOMPRESSION) == 0 else {
            return false
        }

        let resourceForkDescriptor = open(name + _PATH_RSRCFORKSPEC, O_WRONLY | O_CREAT, 0o666)
        guard resourceForkDescriptor >= 0 else {
            return false
        }
        defer {
            close(resourceForkDescriptor)
        }

        var written: Int
        repeat {
            // TODO: handle partial writes smarter
            written = pwrite(resourceForkDescriptor, data, data.count, 0)
            guard written >= 0 else {
                return false
            }
        } while written != data.count

        guard fchflags(descriptor, UInt32(UF_COMPRESSED)) == 0 else {
            return false
        }

        return true
    }
}

extension option {
    init(name: StaticString, has_arg: CInt, flag: UnsafeMutablePointer<CInt>?, val: StringLiteralType) {
        let _option = name.withUTF8Buffer {
            $0.withMemoryRebound(to: CChar.self) {
                option(name: $0.baseAddress, has_arg: has_arg, flag: flag, val: CInt(UnicodeScalar(val)!.value))
            }
        }
        self = _option
    }
}

public struct UnxipOptions {
    var input: String?
    var output: String?
    var compress: Bool = true
   
    public init(input: String?, output: String?) {
        self.input = input
        self.output = output
    }
}

@available(macOS 11.0, *)
public struct Unxip {
    let options: UnxipOptions

    public init(options: UnxipOptions) {
        self.options = options
    }
    
    func async_precondition(_ condition: @autoclosure () async throws -> Bool) async rethrows {
        let result = try await condition()
        precondition(result)
    }

    func dataStream(descriptor: CInt) -> DataStream<BackpressureStream<[UInt8], CountedBackpressure<[UInt8]>>> {
        let stream = BackpressureStream(backpressure: CountedBackpressure(max: 16), of: [UInt8].self)
        let io = DispatchIO(type: .stream, fileDescriptor: descriptor, queue: .main) { _ in
        }

        Task {
            while await withCheckedContinuation({ continuation in
                var chunk = DispatchData.empty
                io.read(offset: 0, length: Int(PIPE_SIZE * 16), queue: .main) { done, data, error in
                    guard error == 0 else {
                        stream.finish(throwing: NSError(domain: NSPOSIXErrorDomain, code: Int(error)))
                        continuation.resume(returning: false)
                        return
                    }

                    chunk.append(data!)

                    if done {
                        if chunk.isEmpty {
                            stream.finish()
                            continuation.resume(returning: false)
                        } else {
                            let chunk = chunk
                            Task {
                                await stream.yield(
                                    [UInt8](unsafeUninitializedCapacity: chunk.count) { buffer, count in
                                        _ = chunk.copyBytes(to: buffer, from: nil)
                                        count = chunk.count
                                    })
                                continuation.resume(returning: true)
                            }
                        }
                    }
                }
            }) {
            }
        }

        return DataStream(data: stream)
    }

    func chunks(from content: DataStream<some AsyncSequence>) -> BackpressureStream<Chunk, CountedBackpressure<Chunk>> {
        let decompressionStream = ConcurrentStream<Void>(consumeResults: true)
        let chunkStream = BackpressureStream(backpressure: CountedBackpressure(max: 16), of: Chunk.self)

        // A consuming reference, but alas we can't express this right now
        let _content = content
        Task {
            var content = _content
            let magic = "pbzx".utf8
            try await async_precondition(try await content.read(magic.count).elementsEqual(magic))
            let chunkSize = try await content.read(UInt64.self)
            var decompressedSize: UInt64 = 0
            var previousYield: Task<Void, Error>?

            repeat {
                decompressedSize = try await content.read(UInt64.self)
                let compressedSize = try await content.read(UInt64.self)

                let block = try await content.read(Int(compressedSize))
                let _decompressedSize = decompressedSize
                let _previousYield = previousYield
                previousYield = await decompressionStream.addTask {
                    let decompressedSize = _decompressedSize
                    let previousYield = _previousYield
                    let chunk = Chunk(data: block, decompressedSize: compressedSize == chunkSize ? nil : Int(decompressedSize))
                    _ = await previousYield?.result
                    await chunkStream.yield(chunk)
                }
            } while decompressedSize == chunkSize
            await decompressionStream.finish()
        }

        return chunkStream
    }

    func files<ChunkStream: AsyncSequence>(in chunkStream: ChunkStream) -> BackpressureStream<File, FileBackpressure> where ChunkStream.Element == Chunk {
        let fileStream = BackpressureStream(backpressure: FileBackpressure(maxSize: 1_000_000_000), of: File.self)
        Task {
            var iterator = chunkStream.makeAsyncIterator()
            var chunk = try! await iterator.next()!
            var position = 0

            func read(size: Int) async -> [UInt8] {
                var result = [UInt8]()
                while result.count < size {
                    if position >= chunk.buffer.endIndex {
                        chunk = try! await iterator.next()!
                        position = 0
                    }
                    result.append(chunk.buffer[chunk.buffer.startIndex + position])
                    position += 1
                }
                return result
            }

            func readOctal(from bytes: [UInt8]) -> Int {
                Int(String(data: Data(bytes), encoding: .utf8)!, radix: 8)!
            }

            while true {
                let magic = await read(size: 6)
                // Yes, cpio.h really defines this global macro
                precondition(magic.elementsEqual(MAGIC.utf8))
                let dev = readOctal(from: await read(size: 6))
                let ino = readOctal(from: await read(size: 6))
                let mode = readOctal(from: await read(size: 6))
                let _ = await read(size: 6)  // uid
                let _ = await read(size: 6)  // gid
                let _ = await read(size: 6)  // nlink
                let _ = await read(size: 6)  // rdev
                let _ = await read(size: 11)  // mtime
                let namesize = readOctal(from: await read(size: 6))
                var filesize = readOctal(from: await read(size: 11))
                let name = String(cString: await read(size: namesize))
                var file = File(dev: dev, ino: ino, mode: mode, name: name)

                while filesize > 0 {
                    if position >= chunk.buffer.endIndex {
                        chunk = try! await iterator.next()!
                        position = 0
                    }
                    let size = min(filesize, chunk.buffer.endIndex - position)
                    file.data.append(chunk.buffer[fromOffset: position, size: size])
                    filesize -= size
                    position += size
                }

                guard file.name != "TRAILER!!!" else {
                    fileStream.finish()
                    return
                }

                await fileStream.yield(file)
            }
        }
        return fileStream
    }

    func parseContent(_ content: DataStream<some AsyncSequence>) async throws {
        let taskStream = ConcurrentStream<Void>()
        let compressionStream = ConcurrentStream<[UInt8]?>(consumeResults: true)

        var hardlinks = [File.Identifier: (String, Task<Void, Error>)]()
        var directories = [Substring: Task<Void, Error>]()

        for try await file in files(in: chunks(from: content)) {
            @Sendable
            func warn(_ result: CInt, _ operation: String) {
                if result != 0 {
                    perror("\(operation) \(file.name) failed")
                }
            }

            // The assumption is that all directories are provided without trailing slashes
            func parentDirectory<S: StringProtocol>(of path: S) -> S.SubSequence {
                path[..<path.lastIndex(of: "/")!]
            }

            // https://bugs.swift.org/browse/SR-15816
            func parentDirectoryTask(for: File) -> Task<Void, Error>? {
                directories[parentDirectory(of: file.name)] ?? directories[String(parentDirectory(of: file.name))[...]]
            }

            @Sendable
            func setStickyBit(on file: File) {
                if file.mode & Int(C_ISVTX) != 0 {
                    warn(chmod(file.name, mode_t(file.mode)), "Setting sticky bit on")
                }
            }

            if file.name == "." {
                continue
            }

            if let (original, originalTask) = hardlinks[file.identifier] {
                let task = parentDirectoryTask(for: file)
                assert(task != nil, file.name)
                await taskStream.addTask {
                    _ = try await (originalTask.value, task?.value)

                    warn(link(original, file.name), "linking")
                }
                continue
            }

            // The types we care about, anyways
            let typeMask = Int(C_ISLNK | C_ISDIR | C_ISREG)
            switch CInt(file.mode & typeMask) {
                case C_ISLNK:
                    let task = parentDirectoryTask(for: file)
                    assert(task != nil, file.name)
                    await taskStream.addTask {
                        try await task?.value

                        warn(symlink(String(data: Data(file.data.map(Array.init).reduce([], +)), encoding: .utf8), file.name), "symlinking")
                        setStickyBit(on: file)
                    }
                case C_ISDIR:
                    let task = parentDirectoryTask(for: file)
                    assert(task != nil || parentDirectory(of: file.name) == ".", file.name)
                    directories[file.name[...]] = await taskStream.addTask {
                        try await task?.value

                        warn(mkdir(file.name, mode_t(file.mode & 0o777)), "creating directory at")
                        setStickyBit(on: file)
                    }
                case C_ISREG:
                    let task = parentDirectoryTask(for: file)
                    assert(task != nil, file.name)
                    hardlinks[file.identifier] = (
                        file.name,
                        await taskStream.addTask {
                            try await task?.value

                            let compressedData =
                                options.compress
                                ? try! await compressionStream.addTask {
                                    await file.compressedData()
                                }.result.get() : nil

                            let fd = open(file.name, O_CREAT | O_WRONLY, mode_t(file.mode & 0o777))
                            if fd < 0 {
                                warn(fd, "creating file at")
                                return
                            }
                            defer {
                                warn(close(fd), "closing")
                                setStickyBit(on: file)
                            }

                            if let compressedData = compressedData,
                                file.write(compressedData: compressedData, toDescriptor: fd)
                            {
                                return
                            }

                            var position = 0
                            outer: for data in file.data {
                                var written = 0
                                // TODO: handle partial writes smarter
                                repeat {
                                    written = data.withUnsafeBytes {
                                        pwrite(fd, $0.baseAddress, data.count, off_t(position))
                                    }
                                    if written < 0 {
                                        warn(-1, "writing chunk to")
                                        break outer
                                    }
                                } while written != data.count
                                position += written
                            }
                        }
                    )
                default:
                    fatalError("\(file.name) with \(file.mode) is a type that is unhandled")
            }
        }

        await taskStream.finish()

        // Run through any stragglers
        for try await _ in taskStream.results {
        }
    }

    func locateContent(in file: inout DataStream<some AsyncSequence>) async throws {
        let fileStart = file.position

        let magic = "xar!".utf8
        try await async_precondition(await file.read(magic.count).elementsEqual(magic))
        let headerSize = try await file.read(UInt16.self)
        try await async_precondition(await file.read(UInt16.self) == 1)  // version
        let tocCompressedSize = try await file.read(UInt64.self)
        let tocDecompressedSize = try await file.read(UInt64.self)
        _ = try await file.read(UInt32.self)  // checksum

        _ = try await file.read(fileStart + Int(headerSize) - file.position)

        let zlibSkip = 2  // Apple's decoder doesn't want to see CMF/FLG (see RFC 1950)
        _ = try await file.read(2)
        var compressedTOC = try await file.read(Int(tocCompressedSize) - zlibSkip)

        let toc = [UInt8](unsafeUninitializedCapacity: Int(tocDecompressedSize)) { buffer, count in
            count = compression_decode_buffer(buffer.baseAddress!, Int(tocDecompressedSize), &compressedTOC, compressedTOC.count, nil, COMPRESSION_ZLIB)
            precondition(count == Int(tocDecompressedSize))
        }

        let document = try! XMLDocument(data: Data(toc))
        let content = try! document.nodes(forXPath: "xar/toc/file").first {
            try! $0.nodes(forXPath: "name").first!.stringValue! == "Content"
        }!
        let contentOffset = Int(try! content.nodes(forXPath: "data/offset").first!.stringValue!)!
        let contentSize = Int(try! content.nodes(forXPath: "data/length").first!.stringValue!)!

        _ = try await file.read(fileStart + Int(headerSize) + Int(tocCompressedSize) + contentOffset - file.position)
        file.cap = file.position + contentSize
    }

    public func run() async throws {
        let handle =
            try options.input.flatMap {
                try FileHandle(forReadingFrom: URL(fileURLWithPath: $0))
            } ?? FileHandle.standardInput

        if let output = options.output {
            guard chdir(output) == 0 else {
                fputs("Failed to access output directory at \(output): \(String(cString: strerror(errno)))", stderr)
                exit(EXIT_FAILURE)
            }
        }

        var file = dataStream(descriptor: handle.fileDescriptor)
        try await locateContent(in: &file)
        try await parseContent(file)
    }
}
