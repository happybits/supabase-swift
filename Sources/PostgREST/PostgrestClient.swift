import _Helpers
import ConcurrencyExtras
import Foundation

public typealias PostgrestError = _Helpers.PostgrestError

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// PostgREST client.
public final class PostgrestClient: Sendable {
  public typealias FetchHandler = @Sendable (_ request: URLRequest) async throws -> (
    Data, URLResponse
  )

  /// The configuration struct for the PostgREST client.
  public struct Configuration: Sendable {
    public var url: URL
    public var schema: String?
    public var headers: [String: String]
    public var fetch: FetchHandler
    public var encoder: JSONEncoder
    public var decoder: JSONDecoder

    let logger: (any SupabaseLogger)?

    /// Initializes a new configuration for the PostgREST client.
    /// - Parameters:
    ///   - url: The URL of the PostgREST server.
    ///   - schema: The schema to use.
    ///   - headers: The headers to include in requests.
    ///   - logger: The logger to use.
    ///   - fetch: The fetch handler to use for requests.
    ///   - encoder: The JSONEncoder to use for encoding.
    ///   - decoder: The JSONDecoder to use for decoding.
    public init(
      url: URL,
      schema: String? = nil,
      headers: [String: String] = [:],
      logger: (any SupabaseLogger)? = nil,
      fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) },
      encoder: JSONEncoder = PostgrestClient.Configuration.jsonEncoder,
      decoder: JSONDecoder = PostgrestClient.Configuration.jsonDecoder
    ) {
      self.url = url
      self.schema = schema
      self.headers = headers
      self.logger = logger
      self.fetch = fetch
      self.encoder = encoder
      self.decoder = decoder
    }
  }

  let _configuration: LockIsolated<Configuration>
  public var configuration: Configuration { _configuration.value }

  /// Creates a PostgREST client with the specified configuration.
  /// - Parameter configuration: The configuration for the client.
  public init(configuration: Configuration) {
    _configuration = LockIsolated(configuration)
    _configuration.withValue {
      $0.headers.merge(Configuration.defaultHeaders) { l, _ in l }
    }
  }

  /// Creates a PostgREST client with the specified parameters.
  /// - Parameters:
  ///   - url: The URL of the PostgREST server.
  ///   - schema: The schema to use.
  ///   - headers: The headers to include in requests.
  ///   - logger: The logger to use.
  ///   - session: The URLSession to use for requests.
  ///   - encoder: The JSONEncoder to use for encoding.
  ///   - decoder: The JSONDecoder to use for decoding.
  public convenience init(
    url: URL,
    schema: String? = nil,
    headers: [String: String] = [:],
    logger: (any SupabaseLogger)? = nil,
    fetch: @escaping FetchHandler = { try await URLSession.shared.data(for: $0) },
    encoder: JSONEncoder = PostgrestClient.Configuration.jsonEncoder,
    decoder: JSONDecoder = PostgrestClient.Configuration.jsonDecoder
  ) {
    self.init(
      configuration: Configuration(
        url: url,
        schema: schema,
        headers: headers,
        logger: logger,
        fetch: fetch,
        encoder: encoder,
        decoder: decoder
      )
    )
  }

  /// Sets the authorization token for the client.
  /// - Parameter token: The authorization token.
  /// - Returns: The PostgrestClient instance.
  @discardableResult
  public func setAuth(_ token: String?) -> PostgrestClient {
    if let token {
      _configuration.withValue { $0.headers["Authorization"] = "Bearer \(token)" }
    } else {
      _ = _configuration.withValue { $0.headers.removeValue(forKey: "Authorization") }
    }
    return self
  }

  /// Performs a query on a table or a view.
  /// - Parameter table: The table or view name to query.
  /// - Returns: A PostgrestQueryBuilder instance.
  public func from(_ table: String) -> PostgrestQueryBuilder {
    PostgrestQueryBuilder(
      configuration: configuration,
      request: .init(path: table, method: .get, headers: configuration.headers)
    )
  }

  /// Performs a function call.
  /// - Parameters:
  ///   - fn: The function name to call.
  ///   - params: The parameters to pass to the function call.
  ///   - count: Count algorithm to use to count rows returned by the function.
  ///             Only applicable for set-returning functions.
  /// - Returns: A PostgrestFilterBuilder instance.
  /// - Throws: An error if the function call fails.
  public func rpc(
    _ fn: String,
    params: some Encodable & Sendable,
    count: CountOption? = nil
  ) throws -> PostgrestFilterBuilder {
    try PostgrestRpcBuilder(
      configuration: configuration,
      request: Request(path: "/rpc/\(fn)", method: .post, headers: configuration.headers)
    ).rpc(params: params, count: count)
  }

  /// Performs a function call.
  /// - Parameters:
  ///   - fn: The function name to call.
  ///   - count: Count algorithm to use to count rows returned by the function.
  ///            Only applicable for set-returning functions.
  /// - Returns: A PostgrestFilterBuilder instance.
  /// - Throws: An error if the function call fails.
  public func rpc(
    _ fn: String,
    count: CountOption? = nil
  ) throws -> PostgrestFilterBuilder {
    try rpc(fn, params: NoParams(), count: count)
  }

  /// Select a schema to query or perform an function (rpc) call.
  ///
  /// The schema needs to be on the list of exposed schemas inside Supabase.
  /// - Parameter schema: The schema to query.
  public func schema(_ schema: String) -> PostgrestClient {
    var configuration = configuration
    configuration.schema = schema
    return PostgrestClient(configuration: configuration)
  }
}
