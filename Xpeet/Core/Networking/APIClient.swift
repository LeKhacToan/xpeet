import Foundation

enum APIError: Error {
    case invalidResponse
    case httpStatus(Int)
}

struct APIClient {
    var baseURL: URL
    var session: URLSession = .shared
    var decoder: JSONDecoder = JSONDecoder()

    func get<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> T {
        let (data, response) = try await session.data(from: baseURL.appending(path: path))
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.httpStatus(http.statusCode) }
        return try decoder.decode(T.self, from: data)
    }
}
