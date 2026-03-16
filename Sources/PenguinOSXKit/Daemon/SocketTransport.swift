import Darwin
import Foundation

enum PenguinSocketTransport {
    private static let socketPathLimit = 103

    static func makeServerSocket(path: String) throws -> Int32 {
        if path.utf8.count > Self.socketPathLimit {
            throw PenguinDaemonError.socketPathTooLong(path)
        }

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw PenguinDaemonError.socketCreateFailed(String(cString: strerror(errno)))
        }

        Darwin.unlink(path)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        self.copyPath(path, into: &addr)

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, addrLen)
            }
        }
        guard bindResult == 0 else {
            let message = String(cString: strerror(errno))
            Darwin.close(fd)
            throw PenguinDaemonError.socketBindFailed(message)
        }

        guard Darwin.listen(fd, 8) == 0 else {
            let message = String(cString: strerror(errno))
            Darwin.close(fd)
            throw PenguinDaemonError.socketListenFailed(message)
        }

        return fd
    }

    static func canConnect(socketPath: String) -> Bool {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }

        return self.makeConnection(fd: fd, path: socketPath) == 0
    }

    static func requestResponse(socketPath: String, requestData: Data) throws -> Data {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw PenguinDaemonError.socketCreateFailed(String(cString: strerror(errno)))
        }
        defer { Darwin.close(fd) }

        guard self.makeConnection(fd: fd, path: socketPath) == 0 else {
            throw PenguinDaemonError.socketConnectFailed(String(cString: strerror(errno)))
        }

        try self.writeAll(data: requestData, to: fd)
        shutdown(fd, SHUT_WR)
        return try self.readAll(from: fd)
    }

    static func readAll(from fd: Int32) throws -> Data {
        var buffer = [UInt8](repeating: 0, count: 16_384)
        var data = Data()

        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count == 0 {
                return data
            }
            if count < 0 {
                if errno == EINTR {
                    continue
                }
                throw PenguinDaemonError.socketReadFailed(String(cString: strerror(errno)))
            }
            data.append(buffer, count: count)
        }
    }

    static func writeAll(data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var written = 0
            while written < data.count {
                let count = Darwin.write(fd, baseAddress.advanced(by: written), data.count - written)
                if count < 0 {
                    if errno == EINTR {
                        continue
                    }
                    throw PenguinDaemonError.socketWriteFailed(String(cString: strerror(errno)))
                }
                written += count
            }
        }
    }

    private static func makeConnection(fd: Int32, path: String) -> Int32 {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        self.copyPath(path, into: &addr)

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        return withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, addrLen)
            }
        }
    }

    private static func copyPath(_ path: String, into address: inout sockaddr_un) {
        withUnsafeMutableBytes(of: &address.sun_path) { rawBuffer in
            rawBuffer.initializeMemory(as: CChar.self, repeating: 0)
            path.withCString { cString in
                strncpy(rawBuffer.baseAddress!.assumingMemoryBound(to: CChar.self), cString, rawBuffer.count - 1)
            }
        }
    }
}
