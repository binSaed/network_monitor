import Flutter
import UIKit
import ObjectiveC

struct NativeNetworkRecord {
    let url: String
    let method: String
    let statusCode: Int
    let requestSizeBytes: Int
    let responseSizeBytes: Int
    let timestamp: Int64
    let durationMs: Int64
    let source: String

    func toDict() -> [String: Any] {
        return [
            "url": url,
            "method": method,
            "statusCode": statusCode,
            "requestSizeBytes": requestSizeBytes,
            "responseSizeBytes": responseSizeBytes,
            "timestamp": timestamp,
            "durationMs": durationMs,
            "source": source
        ]
    }
}

class NetworkMonitorURLProtocol: URLProtocol, URLSessionDataDelegate {
    private static let handledKey = "NetworkMonitorHandled"
    static var maxRecords = 500
    private static let queue = DispatchQueue(label: "com.network_monitor.records", attributes: .concurrent)
    private static var _records: [NativeNetworkRecord] = []

    private var dataTask: URLSessionDataTask?
    private var receivedData = Data()
    private var response: URLResponse?
    private var startTime: Date?

    static func drainRecords() -> [NativeNetworkRecord] {
        queue.sync(flags: .barrier) {
            let drained = _records
            _records.removeAll()
            return drained
        }
    }

    static func addRecord(_ record: NativeNetworkRecord) {
        queue.async(flags: .barrier) {
            _records.append(record)
            if _records.count > maxRecords {
                _records.removeFirst(_records.count - maxRecords)
            }
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        if URLProtocol.property(forKey: handledKey, in: request) != nil {
            return false
        }
        guard let scheme = request.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        startTime = Date()
        guard let mutableRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "NetworkMonitor", code: -1))
            return
        }
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutableRequest)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = config.protocolClasses?.filter { $0 != NetworkMonitorURLProtocol.self }
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        dataTask = session.dataTask(with: mutableRequest as URLRequest)
        dataTask?.resume()
    }

    override func stopLoading() {
        dataTask?.cancel()
        dataTask = nil
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.response = response
        receivedData = Data()
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        receivedData.append(data)
        client?.urlProtocol(self, didLoad: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let elapsed = startTime.map { Date().timeIntervalSince($0) } ?? 0
        let httpResponse = response as? HTTPURLResponse

        let record = NativeNetworkRecord(
            url: request.url?.absoluteString ?? "",
            method: request.httpMethod ?? "GET",
            statusCode: httpResponse?.statusCode ?? 0,
            requestSizeBytes: request.httpBody?.count ?? 0,
            responseSizeBytes: receivedData.count,
            timestamp: Int64(Date().timeIntervalSince1970 * 1000),
            durationMs: Int64(elapsed * 1000),
            source: "native_ios"
        )
        NetworkMonitorURLProtocol.addRecord(record)

        if let error = error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
        session.finishTasksAndInvalidate()
    }
}

private var hasSwizzled = false

private func swizzleURLSessionConfiguration() {
    guard !hasSwizzled else { return }
    hasSwizzled = true

    guard let originalMethod = class_getInstanceMethod(
        URLSessionConfiguration.self,
        #selector(getter: URLSessionConfiguration.protocolClasses)
    ) else { return }

    guard let swizzledMethod = class_getInstanceMethod(
        URLSessionConfiguration.self,
        #selector(URLSessionConfiguration.nm_protocolClasses)
    ) else { return }

    method_exchangeImplementations(originalMethod, swizzledMethod)
}

extension URLSessionConfiguration {
    @objc func nm_protocolClasses() -> [AnyClass]? {
        var classes = self.nm_protocolClasses() ?? []
        if !classes.contains(where: { $0 == NetworkMonitorURLProtocol.self }) {
            classes.insert(NetworkMonitorURLProtocol.self, at: 0)
        }
        return classes
    }
}

public class NetworkMonitorPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        URLProtocol.registerClass(NetworkMonitorURLProtocol.self)
        swizzleURLSessionConfiguration()

        let channel = FlutterMethodChannel(
            name: "network_monitor",
            binaryMessenger: registrar.messenger()
        )
        let instance = NetworkMonitorPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getRecords":
            let records = NetworkMonitorURLProtocol.drainRecords()
            result(records.map { $0.toDict() })
        case "setMaxRecords":
            if let args = call.arguments as? [String: Any],
               let max = args["maxRecords"] as? Int {
                NetworkMonitorURLProtocol.maxRecords = max
            }
            result(nil)
        case "getTrafficStats":
            result(["txBytes": -1, "rxBytes": -1])
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
