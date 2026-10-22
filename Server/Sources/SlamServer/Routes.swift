import Foundation
import Hummingbird
import SlamCore

/// Who is calling: the phone syncs; models read, or read and write.
public enum Role: Sendable {
    case phone, read, write
}

public struct Tokens: Sendable {
    public var phone: String
    public var read: String
    public var write: String

    public init(phone: String, read: String, write: String) {
        self.phone = phone
        self.read = read
        self.write = write
    }

    func role(_ request: Request) -> Role? {
        guard let header = request.headers[.authorization], header.hasPrefix("Bearer ") else { return nil }
        let token = Array(header.dropFirst(7).utf8)
        for (secret, role) in [(phone, Role.phone), (write, .write), (read, .read)] where Self.same(token, Array(secret.utf8)) {
            return role
        }
        return nil
    }

    /// Compares without stopping at the first difference.
    static func same(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard !b.isEmpty, a.count == b.count else { return false }
        return zip(a, b).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

public enum Routes {
    static let maxPhoto = 32 << 20
    /// A few minutes of 1080p from the phone, which sends videos already shrunk.
    static let maxVideo = 1 << 30

    public static func router(_ vault: Vault, _ tokens: Tokens) -> Router<BasicRequestContext> {
        let router = Router()
        router.get("v1/health") { _, _ in "ok" }

        router.post("v1/sync") { request, context -> Response in
            try check(request, tokens, [.phone])
            let body = try await read(request, SyncRequest.self, limit: 64 << 20)
            return try json(await vault.sync(body))
        }

        router.post("v1/photos/missing") { request, context -> Response in
            try check(request, tokens, [.phone])
            let files = try await read(request, [String].self, limit: 1 << 20)
            return try json(await vault.missingPhotos(files))
        }

        // Photos and videos. Both go to disk as they arrive, so a long video never sits in memory whole.
        router.put("v1/photos/:file") { request, context -> Response in
            try check(request, tokens, [.phone])
            let name = try context.parameters.require("file")
            guard Sync.safeFile(name) else { throw HTTPError(.badRequest, message: "not a usable file name") }
            let limit = Photo.isVideo(name) ? maxVideo : maxPhoto
            let partial = await vault.partialURL(name)
            var size = 0
            let sized = request.body.map { buffer -> ByteBuffer in
                size += buffer.readableBytes
                guard size <= limit else { throw HTTPError(.contentTooLarge) }
                return buffer
            }
            do {
                try await FileIO().writeFile(contents: sized, path: partial.path, context: context)
                try await vault.finishPhoto(partial, as: name)
            } catch {
                try? FileManager.default.removeItem(at: partial)
                // The file writer wraps errors from the body, so say plainly when it was too big.
                if size > limit { throw HTTPError(.contentTooLarge) }
                throw error
            }
            return Response(status: .noContent)
        }

        router.get("v1/photos/:file") { request, context -> Response in
            try check(request, tokens, [.phone, .read, .write])
            let name = try context.parameters.require("file")
            guard let url = await vault.photoURL(name) else { throw HTTPError(.notFound) }
            let body = try await FileIO().loadFile(path: url.path, context: context)
            return Response(status: .ok, headers: [.contentType: Photo.contentType(name)], body: body)
        }
        Agent.routes(router, vault, tokens)
        return router
    }

    static func check(_ request: Request, _ tokens: Tokens, _ allowed: [Role]) throws {
        guard let role = tokens.role(request) else { throw HTTPError(.unauthorized) }
        guard allowed.contains(role) else { throw HTTPError(.forbidden) }
    }

    static func read<T: Decodable>(_ request: Request, _ type: T.Type, limit: Int) async throws -> T {
        let buffer = try await request.body.collect(upTo: limit)
        do {
            return try FileStore.decoder.decode(type, from: Data(buffer.readableBytesView))
        } catch {
            throw HTTPError(.badRequest, message: "\(error)")
        }
    }

    static func json<T: Encodable>(_ value: T) throws -> Response {
        let data = try FileStore.encoder.encode(value)
        return Response(status: .ok, headers: [.contentType: "application/json"],
                        body: ResponseBody(byteBuffer: ByteBuffer(bytes: data)))
    }
}
