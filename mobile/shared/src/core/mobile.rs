use std::collections::BTreeMap;

use super::json::{self, Value};
use super::{normalize_server_url, oauth, validate_discovery, Result};

struct Metadata {
    authorization_endpoint: String,
    token_endpoint: String,
    registration_endpoint: String,
    revocation_endpoint: String,
}

struct Pending {
    server: String,
    token_endpoint: String,
    revocation_endpoint: String,
    client_id: String,
    resource: String,
    redirect_uri: String,
    state: String,
    verifier: String,
}

struct Session {
    server: String,
    token_endpoint: String,
    revocation_endpoint: String,
    client_id: String,
    resource: String,
    access_token: String,
    refresh_token: String,
    expires_at: i64,
}

pub fn discovery_request(server_input: &str) -> Result<String> {
    request(
        "GET",
        &oauth::discovery_url(server_input)?,
        None,
        None,
        None,
    )
}

pub fn registration_request(
    server_input: &str,
    discovery_response: &str,
    redirect_uri: &str,
) -> Result<String> {
    let server = normalize_server_url(server_input)?;
    let metadata = metadata(&server, discovery_response)?;
    request(
        "POST",
        &metadata.registration_endpoint,
        Some(&oauth::registration_body("Hive Mobile", redirect_uri)?),
        Some("application/json"),
        None,
    )
}

pub fn authorization_plan(
    server_input: &str,
    discovery_response: &str,
    registration_response: &str,
    redirect_uri: &str,
    state: &str,
    verifier: &str,
) -> Result<String> {
    let server = normalize_server_url(server_input)?;
    let metadata = metadata(&server, discovery_response)?;
    let client_id = json::required_string(&Value::object(registration_response)?, "client_id")?;
    let resource = format!("{server}/api/v1");
    let authorization_url = oauth::authorization_url(
        &metadata.authorization_endpoint,
        &client_id,
        redirect_uri,
        &resource,
        state,
        verifier,
    )?;
    let pending = Pending {
        server,
        token_endpoint: metadata.token_endpoint,
        revocation_endpoint: metadata.revocation_endpoint,
        client_id,
        resource,
        redirect_uri: redirect_uri.to_string(),
        state: state.to_string(),
        verifier: verifier.to_string(),
    }
    .encode();

    Ok(format!(
        "{{\"authorization_url\":\"{}\",\"pending\":\"{}\"}}",
        json::escape(&authorization_url),
        json::escape(&pending)
    ))
}

pub fn token_request(callback_url: &str, pending: &str) -> Result<String> {
    let pending = Pending::decode(pending)?;
    let code = oauth::callback_code(callback_url, &pending.redirect_uri, &pending.state)?;
    request(
        "POST",
        &pending.token_endpoint,
        Some(&oauth::token_body(
            &code,
            &pending.client_id,
            &pending.redirect_uri,
            &pending.resource,
            &pending.verifier,
        )?),
        Some("application/x-www-form-urlencoded"),
        None,
    )
}

pub fn session_from_token(pending: &str, token_response: &str, now: &str) -> Result<String> {
    let pending = Pending::decode(pending)?;
    let token = Value::object(token_response)?;
    let refresh_token = json::optional_string(&token, "refresh_token")?
        .ok_or_else(|| "Hive did not return a renewable sign-in session.".to_string())?;
    Session {
        server: pending.server,
        token_endpoint: pending.token_endpoint,
        revocation_endpoint: pending.revocation_endpoint,
        client_id: pending.client_id,
        resource: pending.resource,
        access_token: json::required_string(&token, "access_token")?,
        refresh_token,
        expires_at: parse_now(now)? + expires_in(&token)?,
    }
    .encode()
}

pub fn refresh_request(session: &str) -> Result<String> {
    let session = Session::decode(session)?;
    request(
        "POST",
        &session.token_endpoint,
        Some(&oauth::refresh_token_body(
            &session.refresh_token,
            &session.client_id,
            &session.resource,
        )?),
        Some("application/x-www-form-urlencoded"),
        None,
    )
}

pub fn session_from_refresh(session: &str, token_response: &str, now: &str) -> Result<String> {
    let mut session = Session::decode(session)?;
    let token = Value::object(token_response)?;
    session.access_token = json::required_string(&token, "access_token")?;
    if let Some(refresh_token) = json::optional_string(&token, "refresh_token")? {
        session.refresh_token = refresh_token;
    }
    session.expires_at = parse_now(now)? + expires_in(&token)?;
    session.encode()
}

pub fn revoke_request(session: &str) -> Result<String> {
    let session = Session::decode(session)?;
    request(
        "POST",
        &session.revocation_endpoint,
        Some(&oauth::revoke_token_body(
            &session.refresh_token,
            &session.client_id,
        )?),
        Some("application/x-www-form-urlencoded"),
        None,
    )
}

pub fn api_request(session: &str, path: &str) -> Result<String> {
    let session = Session::decode(session)?;
    if !path.starts_with('/') || path.contains("//") || path.contains('#') {
        return Err("The application requested an invalid Hive resource.".to_string());
    }
    request(
        "GET",
        &format!("{}{}", session.resource, path),
        None,
        None,
        Some(&format!("Bearer {}", session.access_token)),
    )
}

pub fn session_should_refresh(session: &str, now: &str) -> Result<String> {
    let session = Session::decode(session)?;
    Ok((session.expires_at - parse_now(now)? < 60).to_string())
}

pub fn session_server(session: &str) -> Result<String> {
    Ok(Session::decode(session)?.server)
}

fn request(
    method: &str,
    url: &str,
    body: Option<&str>,
    content_type: Option<&str>,
    authorization: Option<&str>,
) -> Result<String> {
    let body = body
        .map(|value| format!(",\"body\":\"{}\"", json::escape(value)))
        .unwrap_or_default();
    let content_type = content_type
        .map(|value| format!(",\"content_type\":\"{}\"", json::escape(value)))
        .unwrap_or_default();
    let authorization = authorization
        .map(|value| format!(",\"authorization\":\"{}\"", json::escape(value)))
        .unwrap_or_default();
    Ok(format!(
        "{{\"method\":\"{method}\",\"url\":\"{}\",\"accept\":\"application/json\"{body}{content_type}{authorization}}}",
        json::escape(url)
    ))
}

fn metadata(server: &str, response: &str) -> Result<Metadata> {
    let values = Value::object(response)?;
    let issuer = json::required_string(&values, "issuer")?;
    let metadata = Metadata {
        authorization_endpoint: json::required_string(&values, "authorization_endpoint")?,
        token_endpoint: json::required_string(&values, "token_endpoint")?,
        registration_endpoint: json::required_string(&values, "registration_endpoint")?,
        revocation_endpoint: json::required_string(&values, "revocation_endpoint")?,
    };
    validate_discovery(
        server,
        &issuer,
        &metadata.authorization_endpoint,
        &metadata.token_endpoint,
        &metadata.registration_endpoint,
        &metadata.revocation_endpoint,
    )?;
    Ok(metadata)
}

fn expires_in(token: &BTreeMap<String, Value>) -> Result<i64> {
    let value = json::optional_number(token, "expires_in")?.unwrap_or(3600);
    if value <= 0 {
        return Err("Hive returned a response the application could not read.".to_string());
    }
    Ok(value)
}

fn parse_now(now: &str) -> Result<i64> {
    now.parse()
        .map_err(|_| "The native application passed an invalid clock value.".to_string())
}

impl Pending {
    fn decode(input: &str) -> Result<Self> {
        let values = Value::object(input)?;
        Ok(Self {
            server: json::required_string(&values, "server")?,
            token_endpoint: json::required_string(&values, "token_endpoint")?,
            revocation_endpoint: json::required_string(&values, "revocation_endpoint")?,
            client_id: json::required_string(&values, "client_id")?,
            resource: json::required_string(&values, "resource")?,
            redirect_uri: json::required_string(&values, "redirect_uri")?,
            state: json::required_string(&values, "state")?,
            verifier: json::required_string(&values, "verifier")?,
        })
    }

    fn encode(&self) -> String {
        encode_strings(&[
            ("server", &self.server),
            ("token_endpoint", &self.token_endpoint),
            ("revocation_endpoint", &self.revocation_endpoint),
            ("client_id", &self.client_id),
            ("resource", &self.resource),
            ("redirect_uri", &self.redirect_uri),
            ("state", &self.state),
            ("verifier", &self.verifier),
        ])
    }
}

impl Session {
    fn decode(input: &str) -> Result<Self> {
        let values = Value::object(input)?;
        Ok(Self {
            server: json::required_string(&values, "server")?,
            token_endpoint: json::required_string(&values, "token_endpoint")?,
            revocation_endpoint: json::required_string(&values, "revocation_endpoint")?,
            client_id: json::required_string(&values, "client_id")?,
            resource: json::required_string(&values, "resource")?,
            access_token: json::required_string(&values, "access_token")?,
            refresh_token: json::required_string(&values, "refresh_token")?,
            expires_at: values
                .get("expires_at")
                .and_then(Value::number)
                .ok_or_else(|| "The saved sign-in session is invalid.".to_string())?,
        })
    }

    fn encode(&self) -> Result<String> {
        let strings = encode_strings(&[
            ("server", &self.server),
            ("token_endpoint", &self.token_endpoint),
            ("revocation_endpoint", &self.revocation_endpoint),
            ("client_id", &self.client_id),
            ("resource", &self.resource),
            ("access_token", &self.access_token),
            ("refresh_token", &self.refresh_token),
        ]);
        Ok(format!(
            "{},\"expires_at\":{}}}",
            strings.trim_end_matches('}'),
            self.expires_at
        ))
    }
}

fn encode_strings(values: &[(&str, &str)]) -> String {
    let fields = values
        .iter()
        .map(|(key, value)| format!("\"{key}\":\"{}\"", json::escape(value)))
        .collect::<Vec<_>>()
        .join(",");
    format!("{{{fields}}}")
}

#[cfg(test)]
mod tests {
    use super::*;

    const SERVER: &str = "https://hive.example.com";
    const REDIRECT: &str = "dev.tuist.hive://oauth2redirect";
    const DISCOVERY: &str = concat!(
        "{\"issuer\":\"https://hive.example.com\",",
        "\"authorization_endpoint\":\"https://hive.example.com/oauth2/authorize\",",
        "\"token_endpoint\":\"https://hive.example.com/oauth2/token\",",
        "\"registration_endpoint\":\"https://hive.example.com/oauth2/register\",",
        "\"revocation_endpoint\":\"https://hive.example.com/oauth2/revoke\"}"
    );

    #[test]
    fn plans_the_complete_sign_in_and_api_lifecycle() {
        assert!(discovery_request(SERVER).unwrap().contains("well-known"));
        assert!(registration_request(SERVER, DISCOVERY, REDIRECT)
            .unwrap()
            .contains("token_endpoint_auth_method"));

        let plan = authorization_plan(
            SERVER,
            DISCOVERY,
            "{\"client_id\":\"mobile-client\"}",
            REDIRECT,
            "01234567890123456789012345678901",
            "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
        )
        .unwrap();
        let plan = Value::object(&plan).unwrap();
        let pending = json::required_string(&plan, "pending").unwrap();
        let token_request = token_request(
            "dev.tuist.hive://oauth2redirect?code=code&state=01234567890123456789012345678901",
            &pending,
        )
        .unwrap();
        assert!(token_request.contains("code_verifier"));

        let session = session_from_token(
            &pending,
            "{\"access_token\":\"access\",\"refresh_token\":\"refresh\",\"expires_in\":3600}",
            "1000",
        )
        .unwrap();
        assert_eq!(session_server(&session).unwrap(), SERVER);
        assert_eq!(session_should_refresh(&session, "4540").unwrap(), "false");
        assert_eq!(session_should_refresh(&session, "4550").unwrap(), "true");
        assert!(api_request(&session, "/me")
            .unwrap()
            .contains("Bearer access"));
        assert!(refresh_request(&session).unwrap().contains("refresh_token"));
        assert!(revoke_request(&session).unwrap().contains("oauth2/revoke"));
    }

    #[test]
    fn rejects_metadata_from_another_origin() {
        let discovery = DISCOVERY.replace(
            "https://hive.example.com/oauth2/authorize",
            "https://attacker.example/authorize",
        );
        assert!(registration_request(SERVER, &discovery, REDIRECT).is_err());
    }
}
