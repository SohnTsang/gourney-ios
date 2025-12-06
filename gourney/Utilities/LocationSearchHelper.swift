// Utilities/LocationSearchHelper.swift
// Smart location detection for search queries
// ✅ Supports: English, Japanese (日本語), Chinese (中文)

import Foundation
import CoreLocation

struct LocationData {
    let center: CLLocationCoordinate2D
    let radius: Int  // meters
    let displayName: String
}

struct LocationDetectionResult {
    let cleanedQuery: String      // Query with location word removed
    let location: LocationData?   // Detected location (nil if none)
    let originalQuery: String     // Original query
    let matchedKeyword: String?   // The keyword that matched
    
    var hasLocation: Bool { location != nil }
}

final class LocationSearchHelper {
    static let shared = LocationSearchHelper()
    
    // MARK: - Location Database
    // Maps multiple keywords (EN/JA/ZH) to same location
    
    private struct LocationEntry {
        let keywords: [String]  // All variations (en, ja, zh-hans, zh-hant)
        let data: LocationData
    }
    
    private let locationEntries: [LocationEntry] = [
        // === TOKYO DISTRICTS ===
        // Radii reduced: districts ~2-3km, not 5km (to avoid overlapping with neighbors)
        LocationEntry(
            keywords: ["shibuya", "渋谷", "涩谷", "澀谷"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.6580, longitude: 139.7016), radius: 2_500, displayName: "Shibuya")
        ),
        LocationEntry(
            keywords: ["shinjuku", "新宿"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.6938, longitude: 139.7034), radius: 3_000, displayName: "Shinjuku")
        ),
        LocationEntry(
            keywords: ["roppongi", "六本木"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.6628, longitude: 139.7313), radius: 2_000, displayName: "Roppongi")
        ),
        LocationEntry(
            keywords: ["ginza", "銀座", "银座"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.6717, longitude: 139.7649), radius: 2_000, displayName: "Ginza")
        ),
        LocationEntry(
            keywords: ["akihabara", "秋葉原", "秋叶原"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.7023, longitude: 139.7745), radius: 2_000, displayName: "Akihabara")
        ),
        LocationEntry(
            keywords: ["ikebukuro", "池袋"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.7295, longitude: 139.7109), radius: 3_000, displayName: "Ikebukuro")
        ),
        LocationEntry(
            keywords: ["harajuku", "原宿"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.6702, longitude: 139.7027), radius: 1_500, displayName: "Harajuku")
        ),
        LocationEntry(
            keywords: ["ebisu", "恵比寿", "惠比寿"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.6467, longitude: 139.7103), radius: 2_000, displayName: "Ebisu")
        ),
        LocationEntry(
            keywords: ["meguro", "目黒", "目黑"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.6340, longitude: 139.7158), radius: 2_500, displayName: "Meguro")
        ),
        LocationEntry(
            keywords: ["ueno", "上野"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.7141, longitude: 139.7774), radius: 2_500, displayName: "Ueno")
        ),
        LocationEntry(
            keywords: ["asakusa", "浅草"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.7148, longitude: 139.7967), radius: 2_000, displayName: "Asakusa")
        ),
        LocationEntry(
            keywords: ["shimokitazawa", "下北沢", "下北泽"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.6618, longitude: 139.6682), radius: 1_500, displayName: "Shimokitazawa")
        ),
        LocationEntry(
            keywords: ["nakameguro", "中目黒", "中目黑"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.6442, longitude: 139.6988), radius: 1_500, displayName: "Nakameguro")
        ),
        LocationEntry(
            keywords: ["daikanyama", "代官山"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.6486, longitude: 139.7030), radius: 1_000, displayName: "Daikanyama")
        ),
        LocationEntry(
            keywords: ["azabu", "麻布"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.6553, longitude: 139.7368), radius: 2_000, displayName: "Azabu")
        ),
        LocationEntry(
            keywords: ["nihonbashi", "日本橋", "日本桥"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.6839, longitude: 139.7744), radius: 2_000, displayName: "Nihonbashi")
        ),
        LocationEntry(
            keywords: ["tsukiji", "築地", "筑地"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.6654, longitude: 139.7707), radius: 1_500, displayName: "Tsukiji")
        ),
        LocationEntry(
            keywords: ["odaiba", "お台場", "台场", "台場"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.6267, longitude: 139.7762), radius: 3_000, displayName: "Odaiba")
        ),
        LocationEntry(
            keywords: ["shinagawa", "品川"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.6284, longitude: 139.7388), radius: 2_500, displayName: "Shinagawa")
        ),
        LocationEntry(
            keywords: ["gotanda", "五反田"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.6264, longitude: 139.7236), radius: 1_500, displayName: "Gotanda")
        ),
        LocationEntry(
            keywords: ["kichijoji", "吉祥寺"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.7030, longitude: 139.5795), radius: 2_000, displayName: "Kichijoji")
        ),
        LocationEntry(
            keywords: ["jiyugaoka", "自由が丘", "自由之丘"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.6076, longitude: 139.6686), radius: 1_500, displayName: "Jiyugaoka")
        ),
        LocationEntry(
            keywords: ["yoyogi", "代々木", "代代木"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.6833, longitude: 139.7020), radius: 2_000, displayName: "Yoyogi")
        ),
        LocationEntry(
            keywords: ["akasaka", "赤坂"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.7370), radius: 1_500, displayName: "Akasaka")
        ),
        LocationEntry(
            keywords: ["marunouchi", "丸の内", "丸之内"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671), radius: 1_500, displayName: "Marunouchi")
        ),
        LocationEntry(
            keywords: ["toyosu", "豊洲"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.6532, longitude: 139.7917), radius: 2_000, displayName: "Toyosu")
        ),
        
        // === OSAKA DISTRICTS ===
        LocationEntry(
            keywords: ["umeda", "梅田"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 34.7055, longitude: 135.4983), radius: 2_500, displayName: "Umeda")
        ),
        LocationEntry(
            keywords: ["namba", "難波", "难波"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 34.6657, longitude: 135.5013), radius: 2_000, displayName: "Namba")
        ),
        LocationEntry(
            keywords: ["shinsaibashi", "心斎橋", "心斋桥"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 34.6752, longitude: 135.5006), radius: 2_000, displayName: "Shinsaibashi")
        ),
        LocationEntry(
            keywords: ["dotonbori", "道頓堀", "道顿堀"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 34.6687, longitude: 135.5030), radius: 1_000, displayName: "Dotonbori")
        ),
        LocationEntry(
            keywords: ["tennoji", "天王寺"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 34.6467, longitude: 135.5133), radius: 2_000, displayName: "Tennoji")
        ),
        LocationEntry(
            keywords: ["shinsekai", "新世界"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 34.6522, longitude: 135.5062), radius: 1_000, displayName: "Shinsekai")
        ),
        
        // === KYOTO DISTRICTS ===
        LocationEntry(
            keywords: ["gion", "祇園", "祇园"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.0037, longitude: 135.7759), radius: 1_500, displayName: "Gion")
        ),
        LocationEntry(
            keywords: ["kawaramachi", "河原町"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.0039, longitude: 135.7686), radius: 2_000, displayName: "Kawaramachi")
        ),
        LocationEntry(
            keywords: ["arashiyama", "嵐山", "岚山"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.0094, longitude: 135.6660), radius: 2_000, displayName: "Arashiyama")
        ),
        LocationEntry(
            keywords: ["kiyomizu", "清水"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 34.9948, longitude: 135.7850), radius: 1_500, displayName: "Kiyomizu")
        ),
        
        // === SINGAPORE DISTRICTS ===
        LocationEntry(
            keywords: ["orchard", "乌节", "烏節"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 1.3048, longitude: 103.8318), radius: 2_000, displayName: "Orchard")
        ),
        LocationEntry(
            keywords: ["marina bay", "marinabay", "滨海湾", "濱海灣"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 1.2834, longitude: 103.8607), radius: 2_000, displayName: "Marina Bay")
        ),
        LocationEntry(
            keywords: ["sentosa", "圣淘沙", "聖淘沙"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 1.2494, longitude: 103.8303), radius: 3_000, displayName: "Sentosa")
        ),
        LocationEntry(
            keywords: ["bugis", "武吉士"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 1.3008, longitude: 103.8553), radius: 1_500, displayName: "Bugis")
        ),
        LocationEntry(
            keywords: ["jurong", "裕廊"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 1.3329, longitude: 103.7436), radius: 4_000, displayName: "Jurong")
        ),
        LocationEntry(
            keywords: ["chinatown", "牛车水", "牛車水"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 1.2836, longitude: 103.8443), radius: 1_500, displayName: "Chinatown")
        ),
        LocationEntry(
            keywords: ["clarke quay", "clarkequay", "克拉码头", "克拉碼頭"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 1.2906, longitude: 103.8465), radius: 1_000, displayName: "Clarke Quay")
        ),
        LocationEntry(
            keywords: ["little india", "littleindia", "小印度"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 1.3066, longitude: 103.8518), radius: 1_500, displayName: "Little India")
        ),
        LocationEntry(
            keywords: ["holland village", "hollandvillage", "荷兰村", "荷蘭村"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 1.3109, longitude: 103.7958), radius: 1_500, displayName: "Holland Village")
        ),
        LocationEntry(
            keywords: ["tiong bahru", "tiongbahru", "中峇鲁", "中峇魯"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 1.2863, longitude: 103.8273), radius: 1_500, displayName: "Tiong Bahru")
        ),
        LocationEntry(
            keywords: ["raffles place", "rafflesplace", "莱佛士坊", "萊佛士坊"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 1.2840, longitude: 103.8514), radius: 1_500, displayName: "Raffles Place")
        ),
        LocationEntry(
            keywords: ["tanjong pagar", "tanjongpagar", "丹戎巴葛"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 1.2764, longitude: 103.8463), radius: 1_500, displayName: "Tanjong Pagar")
        ),
        
        // === HONG KONG DISTRICTS ===
        LocationEntry(
            keywords: ["causeway bay", "causewaybay", "铜锣湾", "銅鑼灣"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 22.2783, longitude: 114.1827), radius: 2_000, displayName: "Causeway Bay")
        ),
        LocationEntry(
            keywords: ["tsim sha tsui", "tsimshatsui", "tst", "尖沙咀"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 22.2988, longitude: 114.1722), radius: 2_000, displayName: "Tsim Sha Tsui")
        ),
        LocationEntry(
            keywords: ["mongkok", "mong kok", "旺角"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694), radius: 1_500, displayName: "Mongkok")
        ),
        LocationEntry(
            keywords: ["wan chai", "wanchai", "湾仔", "灣仔"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 22.2783, longitude: 114.1747), radius: 1_500, displayName: "Wan Chai")
        ),
        LocationEntry(
            keywords: ["admiralty", "金钟", "金鐘"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 22.2790, longitude: 114.1654), radius: 1_500, displayName: "Admiralty")
        ),
        LocationEntry(
            keywords: ["central", "中环", "中環"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 22.2819, longitude: 114.1580), radius: 2_000, displayName: "Central")
        ),
        LocationEntry(
            keywords: ["lan kwai fong", "lankwaifong", "兰桂坊", "蘭桂坊"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 22.2809, longitude: 114.1555), radius: 500, displayName: "Lan Kwai Fong")
        ),
        LocationEntry(
            keywords: ["soho", "苏豪", "蘇豪"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 22.2829, longitude: 114.1517), radius: 500, displayName: "SoHo")
        ),
        LocationEntry(
            keywords: ["jordan", "佐敦"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 22.3049, longitude: 114.1718), radius: 1_500, displayName: "Jordan")
        ),
        LocationEntry(
            keywords: ["sham shui po", "shamsuipo", "深水埗"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 22.3306, longitude: 114.1622), radius: 1_500, displayName: "Sham Shui Po")
        ),
        
        // === CITIES (larger radius) ===
        LocationEntry(
            keywords: ["tokyo", "東京", "东京"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503), radius: 25_000, displayName: "Tokyo")
        ),
        LocationEntry(
            keywords: ["osaka", "大阪"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 34.6937, longitude: 135.5023), radius: 20_000, displayName: "Osaka")
        ),
        LocationEntry(
            keywords: ["kyoto", "京都"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.0116, longitude: 135.7681), radius: 15_000, displayName: "Kyoto")
        ),
        LocationEntry(
            keywords: ["singapore", "新加坡"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 1.3521, longitude: 103.8198), radius: 15_000, displayName: "Singapore")
        ),
        LocationEntry(
            keywords: ["hong kong", "hongkong", "香港"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 22.3193, longitude: 114.1694), radius: 12_000, displayName: "Hong Kong")
        ),
        LocationEntry(
            keywords: ["yokohama", "横浜", "横滨"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.4437, longitude: 139.6380), radius: 15_000, displayName: "Yokohama")
        ),
        LocationEntry(
            keywords: ["fukuoka", "福岡", "福冈"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 33.5902, longitude: 130.4017), radius: 12_000, displayName: "Fukuoka")
        ),
        LocationEntry(
            keywords: ["nagoya", "名古屋"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 35.1815, longitude: 136.9066), radius: 15_000, displayName: "Nagoya")
        ),
        LocationEntry(
            keywords: ["sapporo", "札幌"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 43.0618, longitude: 141.3545), radius: 12_000, displayName: "Sapporo")
        ),
        LocationEntry(
            keywords: ["kobe", "神戸", "神户"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 34.6901, longitude: 135.1956), radius: 12_000, displayName: "Kobe")
        ),
        LocationEntry(
            keywords: ["taipei", "台北"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 25.0330, longitude: 121.5654), radius: 15_000, displayName: "Taipei")
        ),
        LocationEntry(
            keywords: ["seoul", "首尔", "首爾", "서울"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780), radius: 20_000, displayName: "Seoul")
        ),
        LocationEntry(
            keywords: ["bangkok", "曼谷"],
            data: LocationData(center: CLLocationCoordinate2D(latitude: 13.7563, longitude: 100.5018), radius: 20_000, displayName: "Bangkok")
        ),
    ]
    
    // Flattened lookup: keyword -> LocationData
    private lazy var keywordToLocation: [String: LocationData] = {
        var dict: [String: LocationData] = [:]
        for entry in locationEntries {
            for keyword in entry.keywords {
                dict[keyword.lowercased()] = entry.data
            }
        }
        return dict
    }()
    
    // All keywords sorted by length descending (match longer first)
    private lazy var sortedKeywords: [String] = {
        keywordToLocation.keys.sorted { $0.count > $1.count }
    }()
    
    private init() {}
    
    // MARK: - Detection
    
    /// Detect location in query and return cleaned query + location data
    func detect(in query: String) -> LocationDetectionResult {
        let lowercased = query.lowercased().trimmingCharacters(in: .whitespaces)
        
        // Find first matching location (longer matches first)
        for keyword in sortedKeywords {
            if lowercased.contains(keyword) {
                guard let locationData = keywordToLocation[keyword] else { continue }
                
                // Clean query: remove location word
                let cleanedQuery = removeLocationWord(from: query, keyword: keyword)
                
                print("📍 [Location] Detected '\(locationData.displayName)' via keyword '\(keyword)'")
                print("   🔍 Original: '\(query)' → Cleaned: '\(cleanedQuery)'")
                
                return LocationDetectionResult(
                    cleanedQuery: cleanedQuery,
                    location: locationData,
                    originalQuery: query,
                    matchedKeyword: keyword
                )
            }
        }
        
        // No location found
        return LocationDetectionResult(
            cleanedQuery: query,
            location: nil,
            originalQuery: query,
            matchedKeyword: nil
        )
    }
    
    /// Remove location word from query, keeping the rest
    private func removeLocationWord(from query: String, keyword: String) -> String {
        // For CJK characters, simple replacement works
        // For English, use word boundaries
        
        let isCJK = keyword.unicodeScalars.contains { scalar in
            // CJK Unified Ideographs ranges
            (0x4E00...0x9FFF).contains(scalar.value) ||
            (0x3400...0x4DBF).contains(scalar.value) ||
            (0x3040...0x309F).contains(scalar.value) || // Hiragana
            (0x30A0...0x30FF).contains(scalar.value)    // Katakana
        }
        
        if isCJK {
            // Simple case-insensitive replacement for CJK
            return query
                .replacingOccurrences(of: keyword, with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "  ", with: " ")
                .trimmingCharacters(in: .whitespaces)
        } else {
            // Word boundary replacement for English
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b"
            
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(query.startIndex..., in: query)
                let result = regex.stringByReplacingMatches(in: query, range: range, withTemplate: "")
                
                return result
                    .replacingOccurrences(of: "  ", with: " ")
                    .trimmingCharacters(in: .whitespaces)
            }
            
            return query
        }
    }
    
    /// Get location data for a specific keyword (for testing)
    func getLocation(for keyword: String) -> LocationData? {
        keywordToLocation[keyword.lowercased()]
    }
}
