// Native AI Tool Calling Subsystem for Tinycast
// Consolidated tools, registry, web search aggregator, and web fetch parser.

import CoreLocation
import Foundation
import PDFKit

// MARK: - Standard Built-in AITool Definitions
extension AITool {
    static let calculate = AITool(
        name: "calculate",
        description: "Evaluate mathematical expressions, unit conversions, currency exchange rates, cryptocurrencies, date/time differences, percentages, and timezone conversions.",
        parameters: JSONValue([
            "type": "object",
            "properties": [
                "expression": [
                    "type": "string",
                    "description": "The math/currency/conversion/date expression to calculate, e.g. '100 USD in EUR', '25 * 40', 'days until Christmas', '50 miles in km'"
                ]
            ],
            "required": ["expression"]
        ]),
        origin: "Built-in",
        title: "Calculator"
    )

    static let webSearch = AITool(
        name: "web_search",
        description: "Search the web for up-to-date information, documentation, news, or articles using DuckDuckGo.",
        parameters: JSONValue([
            "type": "object",
            "properties": [
                "query": [
                    "type": "string",
                    "description": "The search query"
                ]
            ],
            "required": ["query"]
        ]),
        origin: "Built-in",
        title: "Web Search"
    )

    static let webFetch = AITool(
        name: "web_fetch",
        description: "Fetch and extract the readable markdown text content of a web page by URL.",
        parameters: JSONValue([
            "type": "object",
            "properties": [
                "url": [
                    "type": "string",
                    "description": "The URL of the web page to fetch"
                ],
                "max_characters": [
                    "type": "integer",
                    "description": "Maximum characters to extract (default 4000)"
                ]
            ],
            "required": ["url"]
        ]),
        origin: "Built-in",
        title: "Web Fetch"
    )

    static let getLocation = AITool(
        name: "get_location",
        description: "Get the user's approximate current location (city, region, country, timezone, coordinates).",
        parameters: JSONValue([
            "type": "object",
            "properties": [:]
        ]),
        origin: "Built-in",
        title: "Location"
    )

    static let getWeather = AITool(
        name: "get_weather",
        description: "Get current weather conditions and forecast for a specific location or current location.",
        parameters: JSONValue([
            "type": "object",
            "properties": [
                "location": [
                    "type": "string",
                    "description": "City name, e.g. 'San Francisco', 'London', or 'current' for local weather"
                ],
                "days": [
                    "type": "integer",
                    "description": "Number of forecast days (1 to 7, default 1)"
                ]
            ]
        ]),
        origin: "Built-in",
        title: "Weather"
    )
}

// MARK: - AIToolRegistry.swift
/// Central registry managing all available native tools and their execution.
@MainActor
final class AIToolRegistry {
    static let shared = AIToolRegistry()

    private let searchAggregator: WebSearchAggregator
    private let pageReader: WebPageReader
    private let locationProvider: LocationProvider
    private let weatherService: WeatherService
    private let calculatorRunner: CalculatorToolRunner

    struct ExtensionToolInfo: Sendable {
        let extensionName: String
        let extensionTitle: String
        let iconPath: String?

        init(extensionName: String, extensionTitle: String, iconPath: String?) {
            self.extensionName = extensionName
            self.extensionTitle = extensionTitle
            self.iconPath = iconPath
        }
    }

    var extensionToolsProvider: (() -> [AITool])?
    var extensionToolExecutor: ((AIToolCall) async -> AIToolResult?)?
    var extensionToolInfoProvider: ((String) -> ExtensionToolInfo?)?
    var calculatorEvaluator: (@MainActor (String) -> String?)? {
        didSet {
            calculatorRunner.evaluator = calculatorEvaluator
        }
    }

    func extensionInfo(for toolName: String) -> ExtensionToolInfo? {
        extensionToolInfoProvider?(toolName)
    }

    init(
        searchAggregator: WebSearchAggregator = WebSearchAggregator(),
        pageReader: WebPageReader = WebPageReader(),
        locationProvider: LocationProvider = LocationProvider(),
        weatherService: WeatherService? = nil,
        calculatorRunner: CalculatorToolRunner = CalculatorToolRunner()
    ) {
        self.searchAggregator = searchAggregator
        self.pageReader = pageReader
        self.locationProvider = locationProvider
        self.weatherService = weatherService ?? WeatherService(locationProvider: locationProvider)
        self.calculatorRunner = calculatorRunner
    }

    struct ToolFilter: Sendable {
        let webSearch: Bool
        let calculate: Bool
        let weather: Bool
        let location: Bool
        let extensionTools: Bool

        init(
            webSearch: Bool = true,
            calculate: Bool = true,
            weather: Bool = true,
            location: Bool = true,
            extensionTools: Bool = true
        ) {
            self.webSearch = webSearch
            self.calculate = calculate
            self.weather = weather
            self.location = location
            self.extensionTools = extensionTools
        }
    }

    func tools(matching filter: ToolFilter) -> [AITool] {
        var tools: [AITool] = []
        if filter.webSearch {
            tools.append(.webSearch)
            tools.append(.webFetch)
        }
        if filter.calculate {
            tools.append(.calculate)
        }
        if filter.location {
            tools.append(.getLocation)
        }
        if filter.weather {
            tools.append(.getWeather)
        }
        if filter.extensionTools, let custom = extensionToolsProvider?() {
            tools.append(contentsOf: custom)
        }
        return tools
    }

    /// All tool definitions available for the model to use
    var availableTools: [AITool] {
        tools(matching: ToolFilter())
    }

    /// Executes a tool call asynchronously and returns the formatted result
    func execute(call: AIToolCall) async -> AIToolResult {
        switch call.name {
        case "web_search":
            return await executeWebSearch(call: call)
        case "web_fetch":
            return await executeWebFetch(call: call)
        case "calculate":
            return executeCalculate(call: call)
        case "get_location":
            return await executeGetLocation(call: call)
        case "get_weather":
            return await executeGetWeather(call: call)
        default:
            if let customExecutor = extensionToolExecutor {
                if let result = await customExecutor(call) {
                    return result
                }
            }
            return AIToolResult.failure(call.id, "Unknown tool: \(call.name)")
        }
    }

    private func executeWebSearch(call: AIToolCall) async -> AIToolResult {
        var query = ""
        if let data = call.arguments.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let q = json["query"] as? String {
            query = q
        } else {
            query = call.arguments
        }

        let results = await searchAggregator.search(query: query)
        let formatted = results.prefix(5).map { res in
            "[\(res.title)](\(res.url))\n\(res.snippet)"
        }.joined(separator: "\n\n")

        return AIToolResult(
            callID: call.id,
            content: formatted.isEmpty ? "No search results found for '\(query)'." : formatted,
            isError: false
        )
    }

    private func executeWebFetch(call: AIToolCall) async -> AIToolResult {
        var urlString = ""
        var maxChars = 4000
        if let data = call.arguments.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let u = json["url"] as? String { urlString = u }
            if let m = json["max_characters"] as? Int { maxChars = m }
        }

        guard let url = URL(string: urlString) else {
            return AIToolResult.failure(call.id, "Invalid URL: \(urlString)")
        }

        do {
            let markdown = try await pageReader.read(url: url, maxCharacters: maxChars)
            return AIToolResult(
                callID: call.id,
                content: markdown,
                isError: false
            )
        } catch {
            return AIToolResult.failure(call.id, "Failed to fetch page: \(error.localizedDescription)")
        }
    }

    private func executeCalculate(call: AIToolCall) -> AIToolResult {
        var expr = ""
        if let data = call.arguments.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let e = json["expression"] as? String {
            expr = e
        } else {
            expr = call.arguments
        }

        let output = calculatorRunner.calculate(expression: expr)
        return AIToolResult(
            callID: call.id,
            content: output,
            isError: false
        )
    }

    private func executeGetLocation(call: AIToolCall) async -> AIToolResult {
        if let loc = await locationProvider.getLocation() {
            return AIToolResult(
                callID: call.id,
                content: loc.summary,
                isError: false
            )
        } else {
            return AIToolResult.failure(call.id, "Could not determine location automatically.")
        }
    }

    private func executeGetWeather(call: AIToolCall) async -> AIToolResult {
        var location: String?
        var days = 1
        if let data = call.arguments.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let loc = json["location"] as? String { location = loc }
            if let d = json["days"] as? Int { days = d }
        }

        let output = await weatherService.getWeather(location: location, days: days)
        return AIToolResult(
            callID: call.id,
            content: output,
            isError: false
        )
    }
}

// MARK: - CalculatorToolRunner.swift
/// Fast on-device evaluator for math, units, currencies, and dates.
@MainActor
final class CalculatorToolRunner: Sendable {
    var evaluator: (@MainActor (String) -> String?)?

    init(evaluator: (@MainActor (String) -> String?)? = nil) {
        self.evaluator = evaluator
    }

    func calculate(expression: String) -> String {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Error: Expression cannot be empty."
        }

        if let evaluated = evaluator?(trimmed) {
            return evaluated
        }

        return "Calculation Error: Unable to evaluate '\(trimmed)'. If asking for current live market data or web search, please use web_search."
    }
}

// MARK: - LocationProvider.swift
struct UserLocationInfo: Equatable, Sendable {
    let subLocality: String
    let city: String
    let region: String
    let country: String
    let countryCode: String
    let postalCode: String
    let latitude: Double
    let longitude: Double
    let timezone: String
    let source: String

    init(
        subLocality: String = "",
        city: String,
        region: String,
        country: String,
        countryCode: String,
        postalCode: String = "",
        latitude: Double,
        longitude: Double,
        timezone: String,
        source: String = "Device GPS (CoreLocation)"
    ) {
        self.subLocality = subLocality
        self.city = city
        self.region = region
        self.country = country
        self.countryCode = countryCode
        self.postalCode = postalCode
        self.latitude = latitude
        self.longitude = longitude
        self.timezone = timezone
        self.source = source
    }

    var summary: String {
        var parts: [String] = []
        if !city.isEmpty { parts.append("City: \(city)") }
        if !region.isEmpty { parts.append("Region: \(region)") }
        if !country.isEmpty { parts.append("Country: \(country) (\(countryCode))") }
        if !timezone.isEmpty { parts.append("Timezone: \(timezone)") }
        parts.append("Coordinates: \(String(format: "%.4f", latitude)), \(String(format: "%.4f", longitude))")
        parts.append("Source: \(source)")
        return parts.joined(separator: "\n")
    }
}

final class LocationProvider: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager: CLLocationManager
    private let geocoder: CLGeocoder

    override init() {
        self.manager = CLLocationManager()
        self.geocoder = CLGeocoder()
        super.init()
    }

    func getLocation() async -> UserLocationInfo? {
        if let gpsLocation = await getCoreLocation() {
            return gpsLocation
        }
        return await getIPLocation()
    }

    private func getCoreLocation() async -> UserLocationInfo? {
        let status = manager.authorizationStatus
        guard status == .authorizedAlways || status == .authorized else {
            return nil
        }

        guard let location = manager.location else {
            return nil
        }

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let place = placemarks.first else { return nil }

            return UserLocationInfo(
                subLocality: place.subLocality ?? "",
                city: place.locality ?? place.name ?? "",
                region: place.administrativeArea ?? "",
                country: place.country ?? "",
                countryCode: place.isoCountryCode ?? "",
                postalCode: place.postalCode ?? "",
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                timezone: place.timeZone?.identifier ?? TimeZone.current.identifier,
                source: "CoreLocation (GPS)"
            )
        } catch {
            return nil
        }
    }

    private func getIPLocation() async -> UserLocationInfo? {
        guard let url = URL(string: "http://ip-api.com/json/?fields=status,country,countryCode,regionName,city,zip,lat,lon,timezone") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["status"] as? String == "success" else { return nil }

            let city = json["city"] as? String ?? ""
            let region = json["regionName"] as? String ?? ""
            let country = json["country"] as? String ?? ""
            let countryCode = json["countryCode"] as? String ?? ""
            let zip = json["zip"] as? String ?? ""
            let lat = json["lat"] as? Double ?? 0.0
            let lon = json["lon"] as? Double ?? 0.0
            let tz = json["timezone"] as? String ?? TimeZone.current.identifier

            return UserLocationInfo(
                city: city,
                region: region,
                country: country,
                countryCode: countryCode,
                postalCode: zip,
                latitude: lat,
                longitude: lon,
                timezone: tz,
                source: "IP Geolocation"
            )
        } catch {
            return nil
        }
    }
}

// MARK: - WeatherService.swift
final class WeatherService: Sendable {
    private let session: URLSession
    private let locationProvider: LocationProvider

    init(session: URLSession? = nil, locationProvider: LocationProvider = LocationProvider()) {
        self.locationProvider = locationProvider
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 6
            config.timeoutIntervalForResource = 8
            self.session = URLSession(configuration: config)
        }
    }

    func getWeather(location: String?, days: Int = 1) async -> String {
        let isFahrenheit: Bool = {
            if #available(macOS 13.0, *) {
                return Locale.current.measurementSystem == .us
            } else {
                return Locale.current.usesMetricSystem == false
            }
        }()
        let tempUnit = isFahrenheit ? "fahrenheit" : "celsius"
        let unitSymbol = isFahrenheit ? "°F" : "°C"
        let speedUnit = isFahrenheit ? "mph" : "kmh"

        var targetLat: Double = 0.0
        var targetLon: Double = 0.0
        var resolvedPlace = ""

        let locTrimmed = location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if locTrimmed.isEmpty || locTrimmed.lowercased() == "current" || locTrimmed.lowercased() == "here" {
            if let userLoc = await locationProvider.getLocation() {
                targetLat = userLoc.latitude
                targetLon = userLoc.longitude
                resolvedPlace = [userLoc.city, userLoc.country].filter { !$0.isEmpty }.joined(separator: ", ")
            } else {
                return "Unable to determine current location. Please specify a city name (e.g. 'weather in Paris')."
            }
        } else {
            guard let encoded = locTrimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let geoURL = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(encoded)&count=1&language=en&format=json") else {
                return "Invalid location query: \(locTrimmed)"
            }

            do {
                let (data, response) = try await session.data(from: geoURL)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    return "Could not geocode location '\(locTrimmed)'."
                }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let results = json["results"] as? [[String: Any]],
                      let first = results.first,
                      let lat = first["latitude"] as? Double,
                      let lon = first["longitude"] as? Double else {
                    return "Location '\(locTrimmed)' not found."
                }
                targetLat = lat
                targetLon = lon
                let name = first["name"] as? String ?? locTrimmed
                let country = first["country"] as? String ?? ""
                let admin1 = first["admin1"] as? String ?? ""
                resolvedPlace = [name, admin1, country].filter { !$0.isEmpty }.joined(separator: ", ")
            } catch {
                return "Failed to search location: \(error.localizedDescription)"
            }
        }

        let forecastDays = min(max(days, 1), 7)
        let weatherURLString = "https://api.open-meteo.com/v1/forecast?latitude=\(targetLat)&longitude=\(targetLon)&current=temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max&temperature_unit=\(tempUnit)&wind_speed_unit=\(speedUnit)&precipitation_unit=mm&timeformat=iso8601&timezone=auto&forecast_days=\(forecastDays)"

        guard let weatherURL = URL(string: weatherURLString) else {
            return "Failed to construct weather request URL."
        }

        do {
            let (data, response) = try await session.data(from: weatherURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return "Weather service returned HTTP error."
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return "Invalid response from weather service."
            }

            var output = "Weather for \(resolvedPlace.isEmpty ? "\(targetLat), \(targetLon)" : resolvedPlace):\n\n"

            if let current = json["current"] as? [String: Any] {
                let temp = current["temperature_2m"] as? Double ?? 0
                let apparent = current["apparent_temperature"] as? Double ?? temp
                let humidity = current["relative_humidity_2m"] as? Int ?? 0
                let wind = current["wind_speed_10m"] as? Double ?? 0
                let code = current["weather_code"] as? Int ?? 0
                let desc = Self.descriptionForWeatherCode(code)

                output += "• Current Conditions: \(desc)\n"
                output += "• Temperature: \(Int(round(temp)))\(unitSymbol) (Feels like \(Int(round(apparent)))\(unitSymbol))\n"
                output += "• Humidity: \(humidity)%\n"
                output += "• Wind Speed: \(Int(round(wind))) \(speedUnit)\n"
            }

            if forecastDays > 1, let daily = json["daily"] as? [String: Any],
               let times = daily["time"] as? [String],
               let maxTemps = daily["temperature_2m_max"] as? [Double],
               let minTemps = daily["temperature_2m_min"] as? [Double],
               let codes = daily["weather_code"] as? [Int] {
                let precipProbs = daily["precipitation_probability_max"] as? [Int] ?? []

                output += "\nForecast:\n"
                for i in 0..<min(times.count, forecastDays) {
                    let day = times[i]
                    let maxT = Int(round(maxTemps[i]))
                    let minT = Int(round(minTemps[i]))
                    let condition = Self.descriptionForWeatherCode(codes[i])
                    let rain = (i < precipProbs.count) ? " · Rain: \(precipProbs[i])%" : ""
                    output += "- \(day): \(condition), High: \(maxT)\(unitSymbol), Low: \(minT)\(unitSymbol)\(rain)\n"
                }
            }

            return output
        } catch {
            return "Failed to fetch weather: \(error.localizedDescription)"
        }
    }

    static func descriptionForWeatherCode(_ code: Int) -> String {
        switch code {
        case 0: return "Clear sky"
        case 1: return "Mainly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Foggy"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61: return "Slight rain"
        case 63: return "Moderate rain"
        case 65: return "Heavy rain"
        case 66, 67: return "Freezing rain"
        case 71: return "Slight snow"
        case 73: return "Moderate snow"
        case 75: return "Heavy snow"
        case 77: return "Snow grains"
        case 80, 81, 82: return "Rain showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm with hail"
        default: return "Partly cloudy"
        }
    }
}

// MARK: - HTMLToMarkdownConverter.swift
enum HTMLToMarkdownConverter {
    /// Converts raw HTML string into clean, token-efficient Markdown.
    static func convert(html: String, maxCharacters: Int = 4000) -> String {
        var text = html

        let removePatterns = [
            #"<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>"#,
            #"<style\b[^<]*(?:(?!<\/style>)<[^<]*)*<\/style>"#,
            #"<noscript\b[^<]*(?:(?!<\/noscript>)<[^<]*)*<\/noscript>"#,
            #"<svg\b[^<]*(?:(?!<\/svg>)<[^<]*)*<\/svg>"#,
            #"<nav\b[^<]*(?:(?!<\/nav>)<[^<]*)*<\/nav>"#,
            #"<footer\b[^<]*(?:(?!<\/footer>)<[^<]*)*<\/footer>"#,
            #"<header\b[^<]*(?:(?!<\/header>)<[^<]*)*<\/header>"#,
            #"<aside\b[^<]*(?:(?!<\/aside>)<[^<]*)*<\/aside>"#,
            #"<iframe\b[^<]*(?:(?!<\/iframe>)<[^<]*)*<\/iframe>"#,
            #"<form\b[^<]*(?:(?!<\/form>)<[^<]*)*<\/form>"#,
            #"<a\s+[^>]*href=["']javascript:[^"']*["'][^>]*>.*?<\/a>"#
        ]

        for pattern in removePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "")
            }
        }

        if let articleRegex = try? NSRegularExpression(pattern: #"<article\b[^>]*>(.*?)<\/article>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]),
           let match = articleRegex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            text = String(text[range])
        } else if let mainRegex = try? NSRegularExpression(pattern: #"<main\b[^>]*>(.*?)<\/main>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]),
                  let match = mainRegex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) {
            text = String(text[range])
        }

        let tagsToNewlines = [
            #"<\/(p|div|section|h[1-6]|tr|li|blockquote)>"#: "\n\n",
            #"<br\s*\/?>"# : "\n",
            #"<hr\s*\/?>"# : "\n---\n"
        ]
        for (pattern, replacement) in tagsToNewlines {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
            }
        }

        let linkPattern = #"<a\s+[^>]*href=["']([^"']+)["'][^>]*>(.*?)<\/a>"#
        if let regex = try? NSRegularExpression(pattern: linkPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "[$2]($1)")
        }

        let headingPatterns = [
            #"<h1\b[^>]*>(.*?)<\/h1>"#: "# $1\n\n",
            #"<h2\b[^>]*>(.*?)<\/h2>"#: "## $1\n\n",
            #"<h3\b[^>]*>(.*?)<\/h3>"#: "### $1\n\n",
            #"<h[4-6]\b[^>]*>(.*?)<\/h[4-6]>"#: "#### $1\n\n"
        ]
        for (pattern, replacement) in headingPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: replacement)
            }
        }

        let strongPattern = #"<(strong|b)\b[^>]*>(.*?)<\/(strong|b)>"#
        if let regex = try? NSRegularExpression(pattern: strongPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "**$2**")
        }

        let emPattern = #"<(em|i)\b[^>]*>(.*?)<\/(em|i)>"#
        if let regex = try? NSRegularExpression(pattern: emPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "*$2*")
        }

        let codePattern = #"<code\b[^>]*>(.*?)<\/code>"#
        if let regex = try? NSRegularExpression(pattern: codePattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "`$1`")
        }

        let stripPattern = #"<[^>]+>"#
        if let regex = try? NSRegularExpression(pattern: stripPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            text = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }

        let entities: [String: String] = [
            "&nbsp;": " ",
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&#39;": "'",
            "&mdash;": "—",
            "&ndash;": "–",
            "&hellip;": "…"
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        let lines = text.components(separatedBy: .newlines)
        var cleanedLines: [String] = []
        var emptyCount = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                emptyCount += 1
                if emptyCount <= 2 {
                    cleanedLines.append("")
                }
            } else {
                emptyCount = 0
                cleanedLines.append(trimmed)
            }
        }
        text = cleanedLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        if text.count > maxCharacters {
            let index = text.index(text.startIndex, offsetBy: maxCharacters)
            text = String(text[..<index]) + "\n\n...[Content truncated for token budget]..."
        }

        return text
    }
}

// MARK: - WebPageReader.swift
final class WebPageReader: Sendable {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 10
            config.timeoutIntervalForResource = 15
            self.session = URLSession(configuration: config)
        }
    }

    func read(url: URL, maxCharacters: Int = 4000) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "WebPageReader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response"])
        }

        guard httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 else {
            throw NSError(domain: "WebPageReader", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP error \(httpResponse.statusCode)"])
        }

        let mime = httpResponse.mimeType?.lowercased() ?? ""
        if mime.contains("pdf") || url.pathExtension.lowercased() == "pdf" {
            if let pdfDoc = PDFDocument(data: data) {
                var extractedText = ""
                let pageCount = min(pdfDoc.pageCount, 10)
                for i in 0..<pageCount {
                    if let page = pdfDoc.page(at: i), let pageStr = page.string {
                        extractedText += pageStr + "\n"
                        if extractedText.count >= maxCharacters { break }
                    }
                }
                let truncated = String(extractedText.prefix(maxCharacters))
                return truncated.isEmpty ? "No readable text found in PDF." : truncated
            }
        }

        let encoding: String.Encoding = {
            if let encName = httpResponse.textEncodingName {
                let cfEnc = CFStringConvertIANACharSetNameToEncoding(encName as CFString)
                if cfEnc != kCFStringEncodingInvalidId {
                    return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEnc))
                }
            }
            return .utf8
        }()

        let rawString = String(data: data, encoding: encoding) ?? String(decoding: data, as: UTF8.self)
        return HTMLToMarkdownConverter.convert(html: rawString, maxCharacters: maxCharsFrom(maxCharacters))
    }

    private func maxCharsFrom(_ requested: Int) -> Int {
        min(max(requested, 500), 12000)
    }
}

// MARK: - WebSearchResult.swift
struct WebSearchResult: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let url: String
    let snippet: String

    init(title: String, url: String, snippet: String) {
        self.title = title
        self.url = url
        self.snippet = snippet
    }
}

// MARK: - WebSearchAggregator.swift
final class WebSearchAggregator: Sendable {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 8
            config.timeoutIntervalForResource = 10
            self.session = URLSession(configuration: config)
        }
    }

    func search(query: String) async -> [WebSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return []
            }
            let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            return parseDuckDuckGoHTML(html)
        } catch {
            return []
        }
    }

    private func parseDuckDuckGoHTML(_ html: String) -> [WebSearchResult] {
        var results: [WebSearchResult] = []
        let resultBlockRegex = try? NSRegularExpression(
            pattern: #"<div\s+class="result\s+results_links\s+results_links_deep[^"]*">(.*?)<\/div>\s*<\/div>\s*<\/div>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )

        let linkRegex = try? NSRegularExpression(
            pattern: #"<a\s+class="result__snippet[^"]*"\s+href="([^"]+)"[^>]*>(.*?)<\/a>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )

        let titleRegex = try? NSRegularExpression(
            pattern: #"<a\s+class="result__url[^"]*"\s+href="([^"]+)"[^>]*>(.*?)<\/a>|<h2[^>]*>\s*<a\s+class="result__a[^"]*"\s+href="([^"]+)"[^>]*>(.*?)<\/a>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )

        let matches = resultBlockRegex?.matches(in: html, range: NSRange(html.startIndex..., in: html)) ?? []

        for match in matches {
            guard let blockRange = Range(match.range(at: 1), in: html) else { continue }
            let block = String(html[blockRange])

            var linkURL = ""
            var title = ""
            var snippet = ""

            if let titleMatch = titleRegex?.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)) {
                if titleMatch.numberOfRanges > 3, let r = Range(titleMatch.range(at: 3), in: block), !r.isEmpty {
                    linkURL = String(block[r])
                    if let tRange = Range(titleMatch.range(at: 4), in: block) {
                        title = stripHTMLTags(String(block[tRange]))
                    }
                } else if let r = Range(titleMatch.range(at: 1), in: block), !r.isEmpty {
                    linkURL = String(block[r])
                    if let tRange = Range(titleMatch.range(at: 2), in: block) {
                        title = stripHTMLTags(String(block[tRange]))
                    }
                }
            }

            if let snippetMatch = linkRegex?.firstMatch(in: block, range: NSRange(block.startIndex..., in: block)),
               let sRange = Range(snippetMatch.range(at: 2), in: block) {
                snippet = stripHTMLTags(String(block[sRange]))
            }

            if linkURL.hasPrefix("//duckduckgo.com/l/?uddg=") {
                if let parsed = extractActualURL(from: "https:" + linkURL) {
                    linkURL = parsed
                }
            }

            if !title.isEmpty && !linkURL.isEmpty {
                results.append(WebSearchResult(title: title.trimmingCharacters(in: .whitespacesAndNewlines), url: linkURL, snippet: snippet.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }

        if results.isEmpty {
            let altRegex = try? NSRegularExpression(
                pattern: #"<a\s+class="result__a[^"]*"\s+href="([^"]+)"[^>]*>(.*?)<\/a>.*?<a\s+class="result__snippet[^"]*"[^>]*>(.*?)<\/a>"#,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            )
            let altMatches = altRegex?.matches(in: html, range: NSRange(html.startIndex..., in: html)) ?? []
            for match in altMatches {
                guard match.numberOfRanges >= 4,
                      let urlR = Range(match.range(at: 1), in: html),
                      let titleR = Range(match.range(at: 2), in: html),
                      let snipR = Range(match.range(at: 3), in: html) else { continue }

                var linkURL = String(html[urlR])
                if linkURL.hasPrefix("//duckduckgo.com/l/?uddg=") {
                    if let parsed = extractActualURL(from: "https:" + linkURL) {
                        linkURL = parsed
                    }
                }
                let title = stripHTMLTags(String(html[titleR])).trimmingCharacters(in: .whitespacesAndNewlines)
                let snippet = stripHTMLTags(String(html[snipR])).trimmingCharacters(in: .whitespacesAndNewlines)

                if !title.isEmpty && !linkURL.isEmpty {
                    results.append(WebSearchResult(title: title, url: linkURL, snippet: snippet))
                }
            }
        }

        return results
    }

    private func extractActualURL(from ddgURLString: String) -> String? {
        guard let url = URL(string: ddgURLString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let uddg = components.queryItems?.first(where: { $0.name == "uddg" })?.value else {
            return nil
        }
        return uddg
    }

    private func stripHTMLTags(_ str: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"<[^>]+>"#, options: []) else { return str }
        let clean = regex.stringByReplacingMatches(in: str, options: [], range: NSRange(str.startIndex..., in: str), withTemplate: "")
        return clean
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
