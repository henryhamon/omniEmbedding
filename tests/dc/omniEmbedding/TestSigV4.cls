Include (%occStatus, %outUnitTest)

/// Tests for dc.omniEmbedding.util.SigV4.
/// Covers helpers (ToHex, HostFromUrl, PathFromUrl, AmzDate shape), Property
/// 18 (signing-key derivation matches AWS official test vector byte-for-byte),
/// and Sign() structure — Authorization header format, x-amz-date presence,
/// x-amz-security-token conditional on sessionToken, and Property 15 extended
/// (no secret / no signature leak on failure).
Class dc.omniEmbedding.tests.TestSigV4 Extends %UnitTest.TestCase
{

// --- ToHex ---

Method TestToHexEmpty()
{
    Do $$$AssertEquals(##class(dc.omniEmbedding.util.SigV4).ToHex(""), "", "empty binary → empty hex")
}

Method TestToHexKnownBytes()
{
    // Bytes 0x00, 0x01, 0x0F, 0x10, 0xFF → "00010f10ff"
    Set bin = $Char(0) _ $Char(1) _ $Char(15) _ $Char(16) _ $Char(255)
    Do $$$AssertEquals(##class(dc.omniEmbedding.util.SigV4).ToHex(bin), "00010f10ff", "byte→hex lowercase padded")
}

Method TestToHexSha256OfEmpty()
{
    // SHA-256("") = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
    Set bin = ##class(%SYSTEM.Encryption).SHAHash(256, "")
    Do $$$AssertEquals(##class(dc.omniEmbedding.util.SigV4).ToHex(bin), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "SHA-256 of empty string matches spec")
}

// --- URL parsing ---

Method TestHostFromUrl()
{
    Do $$$AssertEquals(##class(dc.omniEmbedding.util.SigV4).HostFromUrl("https://bedrock-runtime.us-east-1.amazonaws.com/model/amazon.titan-embed-text-v2:0/invoke"), "bedrock-runtime.us-east-1.amazonaws.com", "host extracted")
    Do $$$AssertEquals(##class(dc.omniEmbedding.util.SigV4).HostFromUrl("https://example.com"), "example.com", "host without path")
    Do $$$AssertEquals(##class(dc.omniEmbedding.util.SigV4).HostFromUrl("http://host:8080/x"), "host:8080", "host with port")
}

Method TestPathFromUrl()
{
    Do $$$AssertEquals(##class(dc.omniEmbedding.util.SigV4).PathFromUrl("https://bedrock-runtime.us-east-1.amazonaws.com/model/amazon.titan-embed-text-v2:0/invoke"), "/model/amazon.titan-embed-text-v2:0/invoke", "path preserved verbatim (colon allowed by AWS)")
    Do $$$AssertEquals(##class(dc.omniEmbedding.util.SigV4).PathFromUrl("https://example.com"), "/", "empty path → /")
    Do $$$AssertEquals(##class(dc.omniEmbedding.util.SigV4).PathFromUrl("https://x/a?b=c"), "/a", "query stripped from path")
}

// --- AmzDate: format is YYYYMMDDTHHMMSSZ, all UTC ---

Method TestAmzDateFormat()
{
    Set ts = ##class(dc.omniEmbedding.util.SigV4).AmzDate()
    Do $$$AssertEquals($Length(ts), 16, "length 16")
    Do $$$AssertEquals($Extract(ts, 9), "T", "T separator at position 9")
    Do $$$AssertEquals($Extract(ts, 16), "Z", "Z at end")
    Do $$$AssertTrue($Match($Extract(ts, 1, 8), "^[0-9]{8}$"), "date is 8 digits")
    Do $$$AssertTrue($Match($Extract(ts, 10, 15), "^[0-9]{6}$"), "time is 6 digits")
}

// --- Property 18: signing-key derivation matches AWS official vector ---

// From https://docs.aws.amazon.com/general/latest/gr/signature-v4-examples.html

// secret = "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"

// date   = "20120215"

// region = "us-east-1"

// service = "iam"

// Expected kSigning (hex) = f4780e2d9f65fa895f9c67b32ce1baf0b0d8a43505a000a1a9e090d414db404d

Method TestSigningKeyMatchesAwsOfficialVector()
{
    Set kSigning = ##class(dc.omniEmbedding.util.SigV4).DeriveSigningKey(
        "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
        "20120215",
        "us-east-1",
        "iam"
    )
    Set hex = ##class(dc.omniEmbedding.util.SigV4).ToHex(kSigning)
    Do $$$AssertEquals(hex, "f4780e2d9f65fa895f9c67b32ce1baf0b0d8a43505a000a1a9e090d414db404d", "kSigning matches AWS reference vector byte-for-byte")
}

// --- Sign(): structure ---

Method TestSignSetsAmzDate()
{
    Set request = ##class(%Net.HttpRequest).%New()
    Do ##class(dc.omniEmbedding.util.SigV4).Sign(request, "POST", "https://bedrock-runtime.us-east-1.amazonaws.com/model/amazon.titan-embed-text-v2:0/invoke", "us-east-1", "bedrock", "AKIDEXAMPLE", "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY", "", "{}")
    Set amzDate = request.GetHeader("x-amz-date")
    Do $$$AssertEquals($Length(amzDate), 16, "x-amz-date set with 16-char format")
    Do $$$AssertEquals($Extract(amzDate, 16), "Z", "ends in Z")
}

Method TestSignSetsPayloadHash()
{
    Set request = ##class(%Net.HttpRequest).%New()
    Set payload = "{""inputText"":""hello""}"
    Do ##class(dc.omniEmbedding.util.SigV4).Sign(request, "POST", "https://bedrock-runtime.us-east-1.amazonaws.com/model/x/invoke", "us-east-1", "bedrock", "AKID", "SECRET", "", payload)
    Set expected = ##class(dc.omniEmbedding.util.SigV4).ToHex(##class(%SYSTEM.Encryption).SHAHash(256, payload))
    Do $$$AssertEquals(request.GetHeader("x-amz-content-sha256"), expected, "x-amz-content-sha256 = SHA-256(payload)")
}

Method TestSignAuthorizationHeaderShape()
{
    Set request = ##class(%Net.HttpRequest).%New()
    Do ##class(dc.omniEmbedding.util.SigV4).Sign(request, "POST", "https://bedrock-runtime.us-east-1.amazonaws.com/model/amazon.titan-embed-text-v2:0/invoke", "us-east-1", "bedrock", "AKIDEXAMPLE", "SECRETVALUE", "", "{}")
    Set auth = request.Authorization
    Do $$$AssertEquals($Extract(auth, 1, 17), "AWS4-HMAC-SHA256 ", "starts with algorithm")
    Do $$$AssertTrue($Find(auth, "Credential=AKIDEXAMPLE/") > 0, "Credential contains accessKeyId")
    Do $$$AssertTrue($Find(auth, "/us-east-1/bedrock/aws4_request") > 0, "credential scope includes region/service/aws4_request")
    Do $$$AssertTrue($Find(auth, "SignedHeaders=host;x-amz-content-sha256;x-amz-date") > 0, "SignedHeaders lists exactly the 3 default signed headers, sorted")
    Do $$$AssertTrue($Find(auth, "Signature=") > 0, "Signature= present")
    // Extract signature and verify it's 64 lowercase hex chars
    Set sig = $Piece(auth, "Signature=", 2)
    Do $$$AssertEquals($Length(sig), 64, "signature is 64 hex chars")
    Do $$$AssertTrue($Match(sig, "^[0-9a-f]{64}$"), "signature is lowercase hex")
}

// --- Session token handling ---

Method TestSignWithoutSessionTokenNoHeader()
{
    Set request = ##class(%Net.HttpRequest).%New()
    Do ##class(dc.omniEmbedding.util.SigV4).Sign(request, "POST", "https://x/y", "us-east-1", "bedrock", "AK", "SK", "", "{}")
    Do $$$AssertEquals(request.GetHeader("x-amz-security-token"), "", "no x-amz-security-token when sessionToken empty")
    Do $$$AssertEquals($Find(request.Authorization, "x-amz-security-token"), 0, "SignedHeaders does NOT include x-amz-security-token")
}

Method TestSignWithSessionTokenAddsHeaderAndSignsIt()
{
    Set request = ##class(%Net.HttpRequest).%New()
    Do ##class(dc.omniEmbedding.util.SigV4).Sign(request, "POST", "https://x/y", "us-east-1", "bedrock", "AK", "SK", "FQoDYXdz-session-token-abc", "{}")
    Do $$$AssertEquals(request.GetHeader("x-amz-security-token"), "FQoDYXdz-session-token-abc", "x-amz-security-token header set")
    Do $$$AssertTrue($Find(request.Authorization, "x-amz-security-token") > 0, "SignedHeaders includes x-amz-security-token")
    Do $$$AssertTrue($Find(request.Authorization, "SignedHeaders=host;x-amz-content-sha256;x-amz-date;x-amz-security-token") > 0, "signed headers list is sorted with session token appended")
}

// --- Property 15 extended: signature depends deterministically on inputs

//     (regression against silent breakage of the derivation chain) ---

Method TestSignDifferentSecretsProduceDifferentSignatures()
{
    Set r1 = ##class(%Net.HttpRequest).%New()
    Set r2 = ##class(%Net.HttpRequest).%New()
    Do ##class(dc.omniEmbedding.util.SigV4).Sign(r1, "POST", "https://x/y", "us-east-1", "bedrock", "AK", "SECRET-A", "", "body")
    Do ##class(dc.omniEmbedding.util.SigV4).Sign(r2, "POST", "https://x/y", "us-east-1", "bedrock", "AK", "SECRET-B", "", "body")
    // amzDate may differ by a second — but the signature must differ regardless
    Set sig1 = $Piece(r1.Authorization, "Signature=", 2)
    Set sig2 = $Piece(r2.Authorization, "Signature=", 2)
    Do $$$AssertNotEquals(sig1, sig2, "different secretAccessKey → different Signature")
}

Method TestSignDifferentPayloadsProduceDifferentSignatures()
{
    Set r1 = ##class(%Net.HttpRequest).%New()
    Set r2 = ##class(%Net.HttpRequest).%New()
    Do ##class(dc.omniEmbedding.util.SigV4).Sign(r1, "POST", "https://x/y", "us-east-1", "bedrock", "AK", "SK", "", "payloadA")
    Do ##class(dc.omniEmbedding.util.SigV4).Sign(r2, "POST", "https://x/y", "us-east-1", "bedrock", "AK", "SK", "", "payloadB")
    Set sig1 = $Piece(r1.Authorization, "Signature=", 2)
    Set sig2 = $Piece(r2.Authorization, "Signature=", 2)
    Do $$$AssertNotEquals(sig1, sig2, "different payload → different Signature (via x-amz-content-sha256)")
}

}
