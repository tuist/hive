use std::collections::BTreeMap;

use super::json::{self, Value};
use super::mobile::{
    api_request, authorization_plan, discovery_request, refresh_request, registration_request,
    revoke_request, session_from_refresh, session_from_token, session_should_refresh,
    token_request,
};
use super::Result;

pub fn authorization_start(
    server: &str,
    redirect_uri: &str,
    state: &str,
    verifier: &str,
) -> Result<String> {
    let request = discovery_request(server)?;
    let continuation = encode_strings(&[
        ("operation", "authorization_discovery"),
        ("server", server),
        ("redirect_uri", redirect_uri),
        ("state", state),
        ("verifier", verifier),
    ]);
    Ok(http_effect(&request, &continuation))
}

pub fn callback_start(callback_url: &str, pending: &str) -> Result<String> {
    let request = token_request(callback_url, pending)?;
    let continuation = encode_strings(&[("operation", "callback"), ("pending", pending)]);
    Ok(http_effect(&request, &continuation))
}

pub fn resource_start(session: &str, resource: &str, now: &str) -> Result<String> {
    let resource = Resource::parse(resource)?;
    if session_should_refresh(session, now)? == "true" {
        let request = refresh_request(session)?;
        let continuation = encode_strings(&[
            ("operation", "resource_refresh"),
            ("session", session),
            ("resource", resource.name()),
        ]);
        Ok(http_effect(&request, &continuation))
    } else {
        resource_request(session, resource)
    }
}

pub fn sign_out_start(session: &str) -> Result<String> {
    let request = revoke_request(session)?;
    let continuation = encode_strings(&[("operation", "revoke")]);
    Ok(http_effect(&request, &continuation))
}

pub fn continue_client(
    continuation: &str,
    response: &str,
    status: &str,
    now: &str,
) -> Result<String> {
    ensure_success(response, status)?;
    let values = Value::object(continuation)?;
    match json::required_string(&values, "operation")?.as_str() {
        "authorization_discovery" => continue_authorization_discovery(&values, response),
        "authorization_registration" => continue_authorization_registration(&values, response),
        "callback" => continue_callback(&values, response, now),
        "resource_refresh" => continue_resource_refresh(&values, response, now),
        "resource_response" => continue_resource_response(&values, response),
        "revoke" => Ok("{\"effect\":\"done\"}".to_string()),
        _ => Err("The saved mobile operation is invalid.".to_string()),
    }
}

fn continue_authorization_discovery(
    values: &BTreeMap<String, Value>,
    response: &str,
) -> Result<String> {
    let server = json::required_string(values, "server")?;
    let redirect_uri = json::required_string(values, "redirect_uri")?;
    let state = json::required_string(values, "state")?;
    let verifier = json::required_string(values, "verifier")?;
    let request = registration_request(&server, response, &redirect_uri)?;
    let continuation = encode_strings(&[
        ("operation", "authorization_registration"),
        ("server", &server),
        ("discovery_response", response),
        ("redirect_uri", &redirect_uri),
        ("state", &state),
        ("verifier", &verifier),
    ]);
    Ok(http_effect(&request, &continuation))
}

fn continue_authorization_registration(
    values: &BTreeMap<String, Value>,
    response: &str,
) -> Result<String> {
    let plan = authorization_plan(
        &json::required_string(values, "server")?,
        &json::required_string(values, "discovery_response")?,
        response,
        &json::required_string(values, "redirect_uri")?,
        &json::required_string(values, "state")?,
        &json::required_string(values, "verifier")?,
    )?;
    let plan = Value::object(&plan)?;
    Ok(format!(
        "{{\"effect\":\"browser\",\"authorization_url\":\"{}\",\"pending\":\"{}\"}}",
        json::escape(&json::required_string(&plan, "authorization_url")?),
        json::escape(&json::required_string(&plan, "pending")?)
    ))
}

fn continue_callback(
    values: &BTreeMap<String, Value>,
    response: &str,
    now: &str,
) -> Result<String> {
    let session = session_from_token(&json::required_string(values, "pending")?, response, now)?;
    Ok(format!(
        "{{\"effect\":\"session\",\"session\":\"{}\"}}",
        json::escape(&session)
    ))
}

fn continue_resource_refresh(
    values: &BTreeMap<String, Value>,
    response: &str,
    now: &str,
) -> Result<String> {
    let session = session_from_refresh(&json::required_string(values, "session")?, response, now)?;
    resource_request(
        &session,
        Resource::parse(&json::required_string(values, "resource")?)?,
    )
}

fn continue_resource_response(values: &BTreeMap<String, Value>, response: &str) -> Result<String> {
    let resource = Resource::parse(&json::required_string(values, "resource")?)?;
    let session = json::required_string(values, "session")?;
    let page = json::required_string(values, "page")?
        .parse::<i64>()
        .map_err(|_| invalid_resource_response())?;
    let (data, pagination) = validate_resource_response(resource, response, page)?;
    let data = append_resource_data(values, resource, data)?;

    if let Some(Pagination { page, total_pages }) = pagination {
        if page < total_pages {
            return resource_page_request(&session, resource, page + 1, &data);
        }
    }

    Ok(format!(
        "{{\"effect\":\"resource\",\"resource\":\"{}\",\"session\":\"{}\",\"data\":{data}}}",
        resource.name(),
        json::escape(&session),
        data = data.encode()
    ))
}

fn resource_request(session: &str, resource: Resource) -> Result<String> {
    resource_page_request(session, resource, 1, &Value::Array(Vec::new()))
}

fn resource_page_request(
    session: &str,
    resource: Resource,
    page: i64,
    accumulated: &Value,
) -> Result<String> {
    let request = api_request(session, &resource.path(page))?;
    let page = page.to_string();
    let accumulated = accumulated.encode();
    let continuation = encode_strings(&[
        ("operation", "resource_response"),
        ("session", session),
        ("resource", resource.name()),
        ("page", &page),
        ("accumulated", &accumulated),
    ]);
    Ok(http_effect(&request, &continuation))
}

fn http_effect(request: &str, continuation: &str) -> String {
    format!(
        "{{\"effect\":\"http\",\"request\":{request},\"continuation\":\"{}\"}}",
        json::escape(continuation)
    )
}

fn ensure_success(response: &str, status: &str) -> Result<()> {
    let status = status
        .parse::<u16>()
        .map_err(|_| "The native transport returned an invalid status.".to_string())?;
    if (200..300).contains(&status) {
        return Ok(());
    }
    let description = Value::object(response).ok().and_then(|values| {
        json::optional_string(&values, "error_description")
            .ok()
            .flatten()
    });
    Err(description.unwrap_or_else(|| format!("Hive returned status {status}.")))
}

fn validate_resource_response(
    resource: Resource,
    response: &str,
    expected_page: i64,
) -> Result<(Value, Option<Pagination>)> {
    let response = Value::object(response)?;
    let data = response.get("data").ok_or_else(invalid_resource_response)?;
    match resource {
        Resource::CurrentUser => validate_user(object(data)?)?,
        Resource::Forage => validate_list(data, validate_forage_item)?,
        Resource::Specs => validate_list(data, validate_spec)?,
        Resource::Drops => validate_list(data, validate_drop)?,
        Resource::DropDigests => validate_list(data, validate_digest)?,
    }
    let pagination = if resource.paginated() {
        Some(validate_pagination(&response, expected_page)?)
    } else {
        None
    };
    Ok((data.clone(), pagination))
}

fn append_resource_data(
    values: &BTreeMap<String, Value>,
    resource: Resource,
    data: Value,
) -> Result<Value> {
    if !resource.paginated() {
        return Ok(data);
    }

    let accumulated = json::required_string(values, "accumulated")?;
    let Value::Array(mut accumulated) = Value::parse(&accumulated)? else {
        return Err(invalid_resource_response());
    };
    let Value::Array(mut data) = data else {
        return Err(invalid_resource_response());
    };
    accumulated.append(&mut data);
    Ok(Value::Array(accumulated))
}

fn validate_pagination(
    response: &BTreeMap<String, Value>,
    expected_page: i64,
) -> Result<Pagination> {
    let pagination = response
        .get("pagination")
        .ok_or_else(invalid_resource_response)
        .and_then(object)?;
    let page = positive_number(pagination, "page")?;
    positive_number(pagination, "page_size")?;
    nonnegative_number(pagination, "total_count")?;
    let total_pages = nonnegative_number(pagination, "total_pages")?;

    if page != expected_page || (total_pages > 0 && page > total_pages) {
        return Err(invalid_resource_response());
    }

    Ok(Pagination { page, total_pages })
}

fn positive_number(value: &BTreeMap<String, Value>, key: &str) -> Result<i64> {
    value
        .get(key)
        .and_then(Value::number)
        .filter(|number| *number > 0)
        .ok_or_else(invalid_resource_response)
}

fn nonnegative_number(value: &BTreeMap<String, Value>, key: &str) -> Result<i64> {
    value
        .get(key)
        .and_then(Value::number)
        .filter(|number| *number >= 0)
        .ok_or_else(invalid_resource_response)
}

fn validate_list(
    value: &Value,
    validate: fn(&BTreeMap<String, Value>) -> Result<()>,
) -> Result<()> {
    let Value::Array(values) = value else {
        return Err(invalid_resource_response());
    };
    for value in values {
        validate(object(value)?)?;
    }
    Ok(())
}

fn validate_user(value: &BTreeMap<String, Value>) -> Result<()> {
    required_strings(value, &["id", "email", "role"])?;
    optional_strings(value, &["name"])
}

fn validate_forage_item(value: &BTreeMap<String, Value>) -> Result<()> {
    required_strings(value, &["id", "type", "title", "status", "updated_at"])?;
    optional_strings(
        value,
        &[
            "body",
            "visibility",
            "source_label",
            "external_label",
            "external_url",
            "occurred_at",
        ],
    )?;
    validate_domains(value)
}

fn validate_spec(value: &BTreeMap<String, Value>) -> Result<()> {
    required_strings(
        value,
        &["id", "title", "body", "status", "visibility", "updated_at"],
    )?;
    optional_strings(value, &["summary"])?;
    required_numbers(value, &["number", "revision"])?;
    required_boolean(value, "has_new_activity")?;
    validate_domains(value)
}

fn validate_drop(value: &BTreeMap<String, Value>) -> Result<()> {
    required_strings(value, &["id", "title", "source_type", "url"])?;
    optional_strings(value, &["body", "version", "published_at"])?;
    required_numbers(value, &["number"])?;
    validate_domains(value)
}

fn validate_digest(value: &BTreeMap<String, Value>) -> Result<()> {
    required_strings(
        value,
        &[
            "id",
            "week_start",
            "week_end",
            "title",
            "summary",
            "body",
            "published_at",
        ],
    )?;
    required_numbers(value, &["drop_count"])
}

fn validate_domains(value: &BTreeMap<String, Value>) -> Result<()> {
    let domains = value.get("domains").ok_or_else(invalid_resource_response)?;
    validate_list(domains, |domain| required_strings(domain, &["id", "name"]))
}

fn required_strings(value: &BTreeMap<String, Value>, keys: &[&str]) -> Result<()> {
    for key in keys {
        json::required_string(value, key)?;
    }
    Ok(())
}

fn optional_strings(value: &BTreeMap<String, Value>, keys: &[&str]) -> Result<()> {
    for key in keys {
        json::optional_string(value, key)?;
    }
    Ok(())
}

fn required_numbers(value: &BTreeMap<String, Value>, keys: &[&str]) -> Result<()> {
    for key in keys {
        value
            .get(*key)
            .and_then(Value::number)
            .ok_or_else(invalid_resource_response)?;
    }
    Ok(())
}

fn required_boolean(value: &BTreeMap<String, Value>, key: &str) -> Result<()> {
    match value.get(key) {
        Some(Value::Boolean(_)) => Ok(()),
        _ => Err(invalid_resource_response()),
    }
}

fn object(value: &Value) -> Result<&BTreeMap<String, Value>> {
    match value {
        Value::Object(value) => Ok(value),
        _ => Err(invalid_resource_response()),
    }
}

fn invalid_resource_response() -> String {
    "Hive returned a resource the application could not read.".to_string()
}

fn encode_strings(values: &[(&str, &str)]) -> String {
    format!(
        "{{{}}}",
        values
            .iter()
            .map(|(key, value)| format!("\"{key}\":\"{}\"", json::escape(value)))
            .collect::<Vec<_>>()
            .join(",")
    )
}

#[derive(Clone, Copy)]
enum Resource {
    CurrentUser,
    Forage,
    Specs,
    Drops,
    DropDigests,
}

struct Pagination {
    page: i64,
    total_pages: i64,
}

impl Resource {
    fn parse(value: &str) -> Result<Self> {
        match value {
            "current_user" => Ok(Self::CurrentUser),
            "forage" => Ok(Self::Forage),
            "specs" => Ok(Self::Specs),
            "drops" => Ok(Self::Drops),
            "drop_digests" => Ok(Self::DropDigests),
            _ => Err("The application requested an unknown Hive resource.".to_string()),
        }
    }

    fn name(self) -> &'static str {
        match self {
            Self::CurrentUser => "current_user",
            Self::Forage => "forage",
            Self::Specs => "specs",
            Self::Drops => "drops",
            Self::DropDigests => "drop_digests",
        }
    }

    fn paginated(self) -> bool {
        !matches!(self, Self::CurrentUser)
    }

    fn path(self, page: i64) -> String {
        match self {
            Self::CurrentUser => "/me".to_string(),
            Self::Forage => format!("/forage?page_size=100&page={page}"),
            Self::Specs => format!("/specs?page_size=100&page={page}"),
            Self::Drops => format!("/drops?page_size=100&page={page}"),
            Self::DropDigests => format!("/drops/digests?page_size=100&page={page}"),
        }
    }
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
    fn drives_authorization_and_resources_as_native_effects() {
        let discovery = authorization_start(
            SERVER,
            REDIRECT,
            "01234567890123456789012345678901",
            "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
        )
        .unwrap();
        assert!(request(&discovery).contains("well-known"));

        let registration =
            continue_client(&continuation(&discovery), DISCOVERY, "200", "0").unwrap();
        assert!(request(&registration).contains("oauth2/register"));

        let browser = continue_client(
            &continuation(&registration),
            "{\"client_id\":\"mobile-client\"}",
            "201",
            "0",
        )
        .unwrap();
        let browser = Value::object(&browser).unwrap();
        assert_eq!(
            json::required_string(&browser, "effect").unwrap(),
            "browser"
        );
        let pending = json::required_string(&browser, "pending").unwrap();

        let token = callback_start(
            "dev.tuist.hive://oauth2redirect?code=code&state=01234567890123456789012345678901",
            &pending,
        )
        .unwrap();
        let session = continue_client(
            &continuation(&token),
            "{\"access_token\":\"access\",\"refresh_token\":\"refresh\",\"expires_in\":3600}",
            "200",
            "1000",
        )
        .unwrap();
        let session = json::required_string(&Value::object(&session).unwrap(), "session").unwrap();

        let user = resource_start(&session, "current_user", "1000").unwrap();
        assert!(request(&user).contains("/api/v1/me"));
        let user = continue_client(
            &continuation(&user),
            "{\"data\":{\"id\":\"user\",\"email\":\"test@hive.dev\",\"name\":null,\"role\":\"member\"}}",
            "200",
            "1000",
        )
        .unwrap();
        assert_eq!(
            json::required_string(&Value::object(&user).unwrap(), "effect").unwrap(),
            "resource"
        );
    }

    #[test]
    fn refreshes_before_loading_and_rejects_invalid_resources() {
        let session = concat!(
            "{\"server\":\"https://hive.example.com\",",
            "\"token_endpoint\":\"https://hive.example.com/oauth2/token\",",
            "\"revocation_endpoint\":\"https://hive.example.com/oauth2/revoke\",",
            "\"client_id\":\"client\",\"resource\":\"https://hive.example.com/api/v1\",",
            "\"access_token\":\"access\",\"refresh_token\":\"refresh\",\"expires_at\":1050}"
        );
        let refresh = resource_start(session, "drops", "1000").unwrap();
        assert!(request(&refresh).contains("refresh_token"));
        let drops = continue_client(
            &continuation(&refresh),
            "{\"access_token\":\"new-access\",\"expires_in\":3600}",
            "200",
            "1000",
        )
        .unwrap();
        assert!(request(&drops).contains("/drops?page_size=100&page=1"));
        assert!(continue_client(
            &continuation(&drops),
            "{\"data\":[{\"id\":\"drop\"}]}",
            "200",
            "1000"
        )
        .is_err());
    }

    #[test]
    fn loads_every_resource_page() {
        let session = concat!(
            "{\"server\":\"https://hive.example.com\",",
            "\"token_endpoint\":\"https://hive.example.com/oauth2/token\",",
            "\"revocation_endpoint\":\"https://hive.example.com/oauth2/revoke\",",
            "\"client_id\":\"client\",\"resource\":\"https://hive.example.com/api/v1\",",
            "\"access_token\":\"access\",\"refresh_token\":\"refresh\",\"expires_at\":5000}"
        );
        let first_request = resource_start(session, "drops", "1000").unwrap();
        let second_request = continue_client(
            &continuation(&first_request),
            &drops_page("first", 1, 2, 2),
            "200",
            "1000",
        )
        .unwrap();

        assert!(request(&second_request).contains("/drops?page_size=100&page=2"));

        let result = continue_client(
            &continuation(&second_request),
            &drops_page("second", 2, 2, 2),
            "200",
            "1000",
        )
        .unwrap();
        let result = Value::object(&result).unwrap();
        let Value::Array(drops) = result.get("data").unwrap() else {
            panic!("expected combined drops")
        };

        assert_eq!(drops.len(), 2);
        assert_eq!(
            json::required_string(object(&drops[0]).unwrap(), "id").unwrap(),
            "first"
        );
        assert_eq!(
            json::required_string(object(&drops[1]).unwrap(), "id").unwrap(),
            "second"
        );
    }

    #[test]
    fn returns_server_error_descriptions() {
        let effect = authorization_start(SERVER, REDIRECT, "state", "verifier").unwrap();
        assert_eq!(
            continue_client(
                &continuation(&effect),
                "{\"error_description\":\"Access denied\"}",
                "403",
                "0"
            ),
            Err("Access denied".to_string())
        );
    }

    fn continuation(effect: &str) -> String {
        json::required_string(&Value::object(effect).unwrap(), "continuation").unwrap()
    }

    fn request(effect: &str) -> String {
        let effect = Value::object(effect).unwrap();
        effect.get("request").unwrap().encode()
    }

    fn drops_page(id: &str, page: i64, total_count: i64, total_pages: i64) -> String {
        format!(
            "{{\"data\":[{{\"id\":\"{id}\",\"title\":\"Drop\",\"source_type\":\"rss\",\"url\":\"https://example.com/{id}\",\"number\":{page},\"domains\":[]}}],\"pagination\":{{\"page\":{page},\"page_size\":1,\"total_count\":{total_count},\"total_pages\":{total_pages}}}}}"
        )
    }
}
