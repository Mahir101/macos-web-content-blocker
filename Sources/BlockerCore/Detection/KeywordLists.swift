import Foundation

/// Built-in signal vocabularies. The lists ship small on purpose:
/// the permanent domain list is the high-precision layer, and users
/// extend it via the custom blocklist.
public enum KeywordLists {
    /// High confidence: known adult domains (seed list, extended at
    /// runtime by the blocklist stores).
    public static let knownAdultDomains: [String] = [
        "pornhub.com", "xvideos.com", "xnxx.com", "xhamster.com",
        "redtube.com", "youporn.com", "spankbang.com", "chaturbate.com",
        "stripchat.com", "onlyfans.com", "brazzers.com", "bangbros.com",
        "youjizz.com", "tube8.com", "beeg.com", "tnaflix.com",
        "eporner.com", "porntrex.com", "hqporner.com", "rule34.xxx",
        "nhentai.net", "hanime.tv", "fapello.com", "motherless.com",
        "cam4.com", "bongacams.com", "livejasmin.com", "myfreecams.com",
    ]

    /// High confidence: brand / site names that appear in tab titles
    /// even when the URL is not readable.
    public static let adultBrandNames: [String] = [
        "pornhub", "xvideos", "xnxx", "xhamster", "redtube", "youporn",
        "spankbang", "chaturbate", "stripchat", "brazzers", "bangbros",
        "livejasmin", "bongacams", "myfreecams", "nhentai", "hqporner",
    ]

    /// Medium confidence: explicit category words. Matched on word
    /// boundaries so "Essex" or "analysis" never trigger.
    public static let categoryKeywords: [String] = [
        "porn", "porno", "pornography", "xxx", "hentai", "milf",
        "hardcore sex", "sex videos", "sex cams", "live sex",
        "adult videos", "adult content", "erotic videos", "camgirl",
        "blowjob", "creampie", "gangbang", "threesome",
    ]

    /// Low confidence on their own: suspicious in aggregate only.
    public static let isolatedKeywords: [String] = [
        "nsfw", "18+", "explicit", "uncensored", "barely legal",
        "webcam show", "strip show", "fetish",
    ]

    /// Cheap pre-filter: if none of these substrings appear anywhere in
    /// the combined text, the page cannot reach the block threshold and
    /// the full scoring pass is skipped.
    public static let prefilterFragments: [String] = [
        "porn", "xxx", "hentai", "sex", "nsfw", "adult", "erotic",
        "milf", "fetish", "cam", "nude", "18+", "explicit", "strip",
        "blowjob", "creampie", "gangbang", "uncensored", "onlyfans",
    ]
}
