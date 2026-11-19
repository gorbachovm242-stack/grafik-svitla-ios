// Мережа: один запит із тайм-аутом і спільний крайній строк на запуск (віджет, кнопка «↻», застосунок).
// Без інтернету iOS буває не відповідає на запит довше за його тайм-аут, а віджет тим часом зупиняють,
// і він лишається старим. Тому чекаємо власними таймерами й самі скасовуємо запит.
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Звідки брати сторінки: на телефоні URLSession, у тестах підставні дані.
public protocol HTTPClient: AnyObject {
    func get(_ url: String, timeoutMs: Double) async throws -> String
}

/// Звичайний клієнт на URLSession: без кешу, з заголовком браузера, помилка HTTP теж помилка.
public final class URLSessionClient: HTTPClient {
    let session: URLSession

    public init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.urlCache = nil
        session = URLSession(configuration: cfg)
    }

    public func get(_ url: String, timeoutMs: Double) async throws -> String {
        guard let u = URL(string: url) else { throw SvitloError.format("Погана адреса \(url)") }
        var request = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: max(1, timeoutMs / 1000))
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await fetch(request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw SvitloError.http(http.statusCode)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func fetch(_ request: URLRequest) async throws -> (Foundation.Data, URLResponse) {
        let holder = TaskHolder()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(Foundation.Data, URLResponse), Error>) in
                let task = session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        cont.resume(throwing: error)
                    } else if let data = data, let response = response {
                        cont.resume(returning: (data, response))
                    } else {
                        cont.resume(throwing: SvitloError.offline)
                    }
                }
                holder.set(task)
                task.resume()
            }
        } onCancel: {
            holder.cancel()
        }
    }
}

/// Запит, який можна скасувати з іншого потоку.
final class TaskHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var cancelled = false

    func set(_ t: URLSessionDataTask) {
        lock.lock()
        task = t
        let stop = cancelled
        lock.unlock()
        if stop { t.cancel() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let t = task
        lock.unlock()
        t?.cancel()
    }
}

/// Одноразові ворота: першим проходить або результат, або таймер.
final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func open() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

/// Як Promise.race з таймером: результат op або помилка тайм-ауту, що прийде раніше.
/// Не чекає, доки op відпустить: завислий запит не тримає віджет.
public func withDeadline<T>(_ ms: Double, _ op: @escaping () async throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<T, Error>) in
        let gate = Gate()
        let work = Task {
            do {
                let value = try await op()
                if gate.open() { cont.resume(returning: value) }
            } catch {
                if gate.open() { cont.resume(throwing: error) }
            }
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(max(0, ms) * 1_000_000))
            if gate.open() {
                cont.resume(throwing: SvitloError.timeout)
                work.cancel()
            }
        }
    }
}

/// Результат op або, якщо він не встиг за ms, запасне значення (збережене). Завислий op не тримає.
public func withFallback<T>(after ms: Double, _ fallback: @escaping () -> T, _ op: @escaping () async -> T) async -> T {
    await withCheckedContinuation { (cont: CheckedContinuation<T, Never>) in
        let gate = Gate()
        let sleeper = Task {
            try? await Task.sleep(nanoseconds: UInt64(max(0, ms) * 1_000_000))
            if Task.isCancelled { return }
            if gate.open() { cont.resume(returning: fallback()) }
        }
        Task {
            let value = await op()
            if gate.open() {
                cont.resume(returning: value)
                sleeper.cancel()
            }
        }
    }
}

/// Один запуск: спільний крайній строк, тайм-аут кожного запиту, і та сама адреса вантажиться лише раз
/// (дві адреси користувача в одній області тягнуть ту саму сторінку обленерго один раз).
public final class Net: @unchecked Sendable {
    let http: HTTPClient
    let deadline: Millis
    let requestMs: Double
    let clock: () -> Millis
    private let lock = NSLock()
    private var memo: [String: Task<String, Error>] = [:]

    public init(http: HTTPClient, budgetMs: Double, requestMs: Double, clock: @escaping () -> Millis) {
        self.http = http
        self.clock = clock
        self.deadline = clock() + budgetMs
        self.requestMs = requestMs
    }

    public var expired: Bool { clock() >= deadline }

    public func load(_ url: String) async throws -> String {
        try await task(for: url).value
    }

    private func task(for url: String) -> Task<String, Error> {
        lock.lock()
        defer { lock.unlock() }
        if let same = memo[url] { return same }
        let task = Task { try await self.loadOnce(url) }
        memo[url] = task
        return task
    }

    private func loadOnce(_ url: String) async throws -> String {
        let left = deadline - clock()
        if left <= 0 { throw SvitloError.expired }
        let ms = min(requestMs, left)
        let http = self.http
        return try await withDeadline(ms) { try await http.get(url, timeoutMs: ms) }
    }
}
