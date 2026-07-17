use std::collections::HashMap;

use super::sha256;
use super::Result;

pub fn discovery_url(server: &str) -> Result<String> {
    let server = super::url::normalize_server_url(server)?;
    Ok(format!("{server}/.well-known/oauth-authorization-server"))
}

pub fn registration_body(client_name: &str, redirect_uri: &str) -> Result<String> {
    validate_redirect_uri(redirect_uri)?;
    Ok(format!(
        concat!(
            "{{\"client_name\":\"{}\",",
            "\"redirect_uris\":[\"{}\"],",
            "\"grant_types\":[\"authorization_code\",\"refresh_token\"],",
            "\"response_types\":[\"code\"],",
            "\"token_endpoint_auth_method\":\"none\"}}"
        ),
        json_escape(client_name),
        json_escape(redirect_uri)
    ))
}

pub fn authorization_url(
    endpoint: &str,
    client_id: &str,
    redirect_uri: &str,
    resource: &str,
    state: &str,
    verifier: &str,
) -> Result<String> {
    validate_redirect_uri(redirect_uri)?;
    validate_verifier(verifier)?;
    if state.len() < 32 || !state.bytes().all(is_unreserved) {
        return Err("The sign-in state is invalid.".to_string());
    }
    if client_id.is_empty() {
        return Err("The registered client identifier is missing.".to_string());
    }

    let challenge = base64_url(&sha256::digest(verifier.as_bytes()));
    let query = form_encode(&[
        ("response_type", "code"),
        ("client_id", client_id),
        ("redirect_uri", redirect_uri),
        ("scope", "mobile"),
        ("resource", resource),
        ("state", state),
        ("code_challenge", &challenge),
        ("code_challenge_method", "S256"),
    ]);
    let separator = if endpoint.contains('?') { '&' } else { '?' };
    Ok(format!("{endpoint}{separator}{query}"))
}

pub fn refresh_token_body(refresh_token: &str, client_id: &str, resource: &str) -> Result<String> {
    if refresh_token.is_empty() || client_id.is_empty() || resource.is_empty() {
        return Err("The saved sign-in session is incomplete.".to_string());
    }

    Ok(form_encode(&[
        ("grant_type", "refresh_token"),
        ("refresh_token", refresh_token),
        ("client_id", client_id),
        ("resource", resource),
    ]))
}

pub fn revoke_token_body(token: &str, client_id: &str) -> Result<String> {
    if token.is_empty() || client_id.is_empty() {
        return Err("The saved sign-in session is incomplete.".to_string());
    }

    Ok(form_encode(&[
        ("token", token),
        ("token_type_hint", "refresh_token"),
        ("client_id", client_id),
    ]))
}

pub fn token_body(
    code: &str,
    client_id: &str,
    redirect_uri: &str,
    resource: &str,
    verifier: &str,
) -> Result<String> {
    validate_redirect_uri(redirect_uri)?;
    validate_verifier(verifier)?;
    if code.is_empty() || client_id.is_empty() {
        return Err("The authorization response is incomplete.".to_string());
    }

    Ok(form_encode(&[
        ("grant_type", "authorization_code"),
        ("code", code),
        ("client_id", client_id),
        ("redirect_uri", redirect_uri),
        ("resource", resource),
        ("code_verifier", verifier),
    ]))
}

pub fn callback_code(
    callback_url: &str,
    expected_redirect_uri: &str,
    expected_state: &str,
) -> Result<String> {
    let (base, query) = callback_url
        .split_once('?')
        .ok_or_else(|| "The authorization response is missing its query.".to_string())?;
    if base != expected_redirect_uri {
        return Err("The authorization response used an unexpected address.".to_string());
    }

    let parameters = decode_query(query)?;
    if let Some(error) = parameters.get("error") {
        return Err(parameters
            .get("error_description")
            .cloned()
            .unwrap_or_else(|| format!("Authorization failed: {error}.")));
    }
    if parameters.get("state").map(String::as_str) != Some(expected_state) {
        return Err("The authorization response state did not match.".to_string());
    }

    parameters
        .get("code")
        .filter(|code| !code.is_empty())
        .cloned()
        .ok_or_else(|| "The authorization response did not include a code.".to_string())
}

fn validate_redirect_uri(redirect_uri: &str) -> Result<()> {
    let (scheme, path) = redirect_uri
        .split_once(':')
        .ok_or_else(|| "The application redirect address is invalid.".to_string())?;
    if !scheme.contains('.') || path != "//oauth2redirect" {
        return Err("The application redirect address is invalid.".to_string());
    }
    Ok(())
}

fn validate_verifier(verifier: &str) -> Result<()> {
    if !(43..=128).contains(&verifier.len()) || !verifier.bytes().all(is_unreserved) {
        return Err("The code verifier is invalid.".to_string());
    }
    Ok(())
}

fn form_encode(parameters: &[(&str, &str)]) -> String {
    parameters
        .iter()
        .map(|(key, value)| format!("{}={}", percent_encode(key), percent_encode(value)))
        .collect::<Vec<_>>()
        .join("&")
}

fn percent_encode(value: &str) -> String {
    let mut output = String::new();
    for byte in value.bytes() {
        if is_unreserved(byte) {
            output.push(byte as char);
        } else {
            output.push_str(&format!("%{byte:02X}"));
        }
    }
    output
}

fn percent_decode(value: &str) -> Result<String> {
    let bytes = value.as_bytes();
    let mut decoded = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        match bytes[index] {
            b'%' if index + 2 < bytes.len() => {
                let high = hex(bytes[index + 1])?;
                let low = hex(bytes[index + 2])?;
                decoded.push((high << 4) | low);
                index += 3;
            }
            b'+' => {
                decoded.push(b' ');
                index += 1;
            }
            byte => {
                decoded.push(byte);
                index += 1;
            }
        }
    }
    String::from_utf8(decoded).map_err(|_| "The authorization response is invalid.".to_string())
}

fn decode_query(query: &str) -> Result<HashMap<String, String>> {
    let mut parameters = HashMap::new();
    for pair in query.split('&') {
        let (key, value) = pair.split_once('=').unwrap_or((pair, ""));
        let key = percent_decode(key)?;
        let value = percent_decode(value)?;
        if parameters.insert(key, value).is_some() {
            return Err("The authorization response contains duplicate values.".to_string());
        }
    }
    Ok(parameters)
}

fn hex(byte: u8) -> Result<u8> {
    match byte {
        b'0'..=b'9' => Ok(byte - b'0'),
        b'a'..=b'f' => Ok(byte - b'a' + 10),
        b'A'..=b'F' => Ok(byte - b'A' + 10),
        _ => Err("The authorization response is invalid.".to_string()),
    }
}

fn base64_url(bytes: &[u8]) -> String {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    let mut output = String::new();
    let mut index = 0;
    while index + 3 <= bytes.len() {
        let value = ((bytes[index] as u32) << 16)
            | ((bytes[index + 1] as u32) << 8)
            | bytes[index + 2] as u32;
        output.push(ALPHABET[((value >> 18) & 63) as usize] as char);
        output.push(ALPHABET[((value >> 12) & 63) as usize] as char);
        output.push(ALPHABET[((value >> 6) & 63) as usize] as char);
        output.push(ALPHABET[(value & 63) as usize] as char);
        index += 3;
    }

    match bytes.len() - index {
        1 => {
            let value = (bytes[index] as u32) << 16;
            output.push(ALPHABET[((value >> 18) & 63) as usize] as char);
            output.push(ALPHABET[((value >> 12) & 63) as usize] as char);
        }
        2 => {
            let value = ((bytes[index] as u32) << 16) | ((bytes[index + 1] as u32) << 8);
            output.push(ALPHABET[((value >> 18) & 63) as usize] as char);
            output.push(ALPHABET[((value >> 12) & 63) as usize] as char);
            output.push(ALPHABET[((value >> 6) & 63) as usize] as char);
        }
        _ => {}
    }
    output
}

fn json_escape(value: &str) -> String {
    let mut output = String::new();
    for character in value.chars() {
        match character {
            '"' => output.push_str("\\\""),
            '\\' => output.push_str("\\\\"),
            '\n' => output.push_str("\\n"),
            '\r' => output.push_str("\\r"),
            '\t' => output.push_str("\\t"),
            value if value.is_control() => output.push_str(&format!("\\u{:04X}", value as u32)),
            value => output.push(value),
        }
    }
    output
}

fn is_unreserved(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'.' | b'_' | b'~')
}

#[cfg(test)]
mod tests {
    use super::*;

    const REDIRECT_URI: &str = "dev.tuist.hive://oauth2redirect";

    #[test]
    fn creates_a_public_native_registration() {
        assert_eq!(
            registration_body("Hive Mobile", REDIRECT_URI).unwrap(),
            concat!(
                "{\"client_name\":\"Hive Mobile\",",
                "\"redirect_uris\":[\"dev.tuist.hive://oauth2redirect\"],",
                "\"grant_types\":[\"authorization_code\",\"refresh_token\"],",
                "\"response_types\":[\"code\"],",
                "\"token_endpoint_auth_method\":\"none\"}"
            )
        );
    }

    #[test]
    fn creates_the_rfc_proof_key_challenge() {
        let url = authorization_url(
            "https://hive.example.com/oauth2/authorize",
            "client",
            REDIRECT_URI,
            "https://hive.example.com/api/v1",
            "01234567890123456789012345678901",
            "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
        )
        .unwrap();

        assert!(url.contains("code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"));
        assert!(url.contains("code_challenge_method=S256"));
        assert!(url.contains("scope=mobile"));
    }

    #[test]
    fn creates_refresh_and_revoke_requests_for_public_clients() {
        assert_eq!(
            refresh_token_body("refresh token", "client", "https://hive.example.com/api/v1")
                .unwrap(),
            "grant_type=refresh_token&refresh_token=refresh%20token&client_id=client&resource=https%3A%2F%2Fhive.example.com%2Fapi%2Fv1"
        );
        assert_eq!(
            revoke_token_body("refresh token", "client").unwrap(),
            "token=refresh%20token&token_type_hint=refresh_token&client_id=client"
        );
    }

    #[test]
    fn validates_the_callback_state_and_code() {
        assert_eq!(
            callback_code(
                "dev.tuist.hive://oauth2redirect?code=the-code&state=the-state",
                REDIRECT_URI,
                "the-state"
            )
            .unwrap(),
            "the-code"
        );
        assert!(callback_code(
            "dev.tuist.hive://oauth2redirect?code=the-code&state=other",
            REDIRECT_URI,
            "the-state"
        )
        .is_err());
    }
}
