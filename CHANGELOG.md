# Changelog

## 0.2.0

- Renamed package to **TrendingHashtag** with Google Trends as a first-class provider option.
- Added configurable time window for trends (`timeWindowHours`), defaulting to 24 hours.
- Added configurable in-memory cache (`cacheDuration`), defaulting to 6 hours.
- Added language filtering (`TrendingLanguage`), defaulting to English, Hindi, and Hinglish while disregarding all other languages.
- Added tag detail lookup API (`tagDetail(for:)`, `TagDetailSearching`) fetching full titles and short descriptions via Wikipedia summary API and feed extraction fallback.
- Retained full backward compatibility for `GoogleTrendsClient` and `GoogleTrends` products.

## 0.1.0

Initial release: independent Swift async feed client, injectable transport, source and binary products, deterministic tests, protected-main CI and version-driven publication.
