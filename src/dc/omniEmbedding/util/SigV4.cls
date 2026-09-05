Include %occStatus

/// AWS Signature Version 4 signer, isolated so it is testable independently of
/// any provider and does not contaminate Base or the OpenAI-compatible family.
/// 
/// Usage:
///   Do ##class(dc.omniEmbedding.util.SigV4).Sign(
///     request, "POST", url, region, "bedrock",
///     accessKeyId, secretAccessKey, sessionToken, payloadBytes)
/// The call SETS request headers: `x-amz-date`, `x-amz-security-token` (if
/// sessionToken non-empty) and `Authorization`. It does NOT send the request.
/// 
/// Security (Property 15 extended): `secretAccessKey`, `sessionToken` and the
/// final `Signature` are NEVER included in exception messages, log lines, or
/// any user-visible output emitted by this class.
Class dc.omniEmbedding.util.SigV4
{

/// Signs the outgoing request in-place. `payload` is the request body as raw
/// bytes (empty string for GET/DELETE with no body).
ClassMethod Sign(request As %Net.HttpRequest, method As %String, url As %String, region As %String, service As %String, accessKeyId As %String, secretAccessKey As %String, sessionToken As %String = "", payload As %String = "")
{
    // 1. Timestamps
    Set amzDate = ..AmzDate()          // e.g. "20260905T131500Z"
    Set dateStamp = $Extract(amzDate, 1, 8)  // "20260905"

    // 2. Parse URL into host + path (Bedrock URLs have no query string)
    Set host = ..HostFromUrl(url)
    Set path = ..PathFromUrl(url)

    // 3. Payload hash (empty payload has a well-known SHA-256)
    Set payloadHash = ..ToHex(##class(%SYSTEM.Encryption).SHAHash(256, payload))

    // 4. Set the mandatory request headers BEFORE building the canonical request
    Do request.SetHeader("x-amz-date", amzDate)
    Do request.SetHeader("x-amz-content-sha256", payloadHash)
    If sessionToken '= "" {
        Do request.SetHeader("x-amz-security-token", sessionToken)
    }

    // 5. Canonical headers — MUST be lowercase name, trimmed value, sorted
    Set canonicalHeaders = ""
    Set signedHeaders = ""
    // For Bedrock: host, x-amz-content-sha256, x-amz-date, (x-amz-security-token)
    Set canonicalHeaders = canonicalHeaders _ "host:" _ host _ $Char(10)
    Set canonicalHeaders = canonicalHeaders _ "x-amz-content-sha256:" _ payloadHash _ $Char(10)
    Set canonicalHeaders = canonicalHeaders _ "x-amz-date:" _ amzDate _ $Char(10)
    Set signedHeaders = "host;x-amz-content-sha256;x-amz-date"
    If sessionToken '= "" {
        Set canonicalHeaders = canonicalHeaders _ "x-amz-security-token:" _ sessionToken _ $Char(10)
        Set signedHeaders = signedHeaders _ ";x-amz-security-token"
    }

    // 6. Canonical request
    Set canonicalRequest = method _ $Char(10)
        _ path _ $Char(10)
        _ "" _ $Char(10)
        _ canonicalHeaders _ $Char(10)
        _ signedHeaders _ $Char(10)
        _ payloadHash

    Set canonicalRequestHash = ..ToHex(##class(%SYSTEM.Encryption).SHAHash(256, canonicalRequest))

    // 7. String to sign
    Set credentialScope = dateStamp _ "/" _ region _ "/" _ service _ "/aws4_request"
    Set stringToSign = "AWS4-HMAC-SHA256" _ $Char(10)
        _ amzDate _ $Char(10)
        _ credentialScope _ $Char(10)
        _ canonicalRequestHash

    // 8. Derive signing key
    Set kSigning = ..DeriveSigningKey(secretAccessKey, dateStamp, region, service)

    // 9. Signature
    Set signature = ..ToHex(##class(%SYSTEM.Encryption).HMACSHA(256, stringToSign, kSigning))

    // 10. Authorization header
    Set authorization = "AWS4-HMAC-SHA256 Credential=" _ accessKeyId _ "/" _ credentialScope
        _ ", SignedHeaders=" _ signedHeaders
        _ ", Signature=" _ signature
    Set request.Authorization = authorization
}

/// Derives the SigV4 signing key: HMAC-SHA256 chain
/// `kSecret = "AWS4"+secretAccessKey`
/// `kDate = HMAC(dateStamp, kSecret)`
/// `kRegion = HMAC(region, kDate)`
/// `kService = HMAC(service, kRegion)`
/// `kSigning = HMAC("aws4_request", kService)`.
/// Returns the raw binary kSigning (32 bytes). Tests use this against the
/// official AWS reference vector to prove the derivation is byte-correct.
ClassMethod DeriveSigningKey(secretAccessKey As %String, dateStamp As %String, region As %String, service As %String) As %String
{
    Set kDate = ##class(%SYSTEM.Encryption).HMACSHA(256, dateStamp, "AWS4"_secretAccessKey)
    Set kRegion = ##class(%SYSTEM.Encryption).HMACSHA(256, region, kDate)
    Set kService = ##class(%SYSTEM.Encryption).HMACSHA(256, service, kRegion)
    Return ##class(%SYSTEM.Encryption).HMACSHA(256, "aws4_request", kService)
}

/// Returns the AWS ISO8601 "basic" timestamp for now in UTC: YYYYMMDDTHHMMSSZ.
/// Extracted as its own method so tests can seed a fixed clock via a subclass.
ClassMethod AmzDate() As %String
{
    // $ZTimestamp is UTC: "66961,49020.123"
    Set utc = $ZTimeStamp
    Set days = $Piece(utc, ",", 1)
    Set secs = $Piece($Piece(utc, ",", 2), ".", 1)
    // Convert to display date+time then strip separators
    Set date = $ZDate(days, 8)     // 20260905
    Set time = $ZTime(secs, 1)     // 13:15:00 (hh:mm:ss)
    Return date _ "T" _ $Replace(time, ":", "") _ "Z"
}

/// Extracts the host (with port if non-default) from a URL.
ClassMethod HostFromUrl(url As %String) As %String [ Internal ]
{
    Set noScheme = url
    If $Find(url, "://") > 0 {
        Set noScheme = $Piece(url, "://", 2)
    }
    Set hostAndPath = $Piece(noScheme, "/", 1)
    Return hostAndPath
}

/// Extracts the canonical path from a URL. Returns "/" when no path is present.
ClassMethod PathFromUrl(url As %String) As %String [ Internal ]
{
    Set noScheme = url
    If $Find(url, "://") > 0 {
        Set noScheme = $Piece(url, "://", 2)
    }
    Set slashAt = $Find(noScheme, "/")
    If slashAt = 0 { Return "/" }
    Set path = "/" _ $Extract(noScheme, slashAt, *)
    // Strip query string — Bedrock has none, but be safe.
    If $Find(path, "?") > 0 {
        Set path = $Piece(path, "?", 1)
    }
    Return path
}

/// Converts raw binary bytes to lowercase hexadecimal string.
/// Note: `$Justify` cannot pad hex with "0" (its third arg is decimal digits,
/// not pad char) — so we prepend "0" and take the last two chars instead.
ClassMethod ToHex(bin As %String) As %String [ Internal ]
{
    Set hex = "", len = $Length(bin)
    For i = 1:1:len {
        Set b = $Ascii($Extract(bin, i))
        Set two = $Extract("0"_$ZConvert($ZHex(b), "L"), *-1, *)
        Set hex = hex _ two
    }
    Return hex
}

}
