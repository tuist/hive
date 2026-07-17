mod json;
mod mobile;
mod oauth;
mod sha256;
mod url;

pub use mobile::{
    api_request, authorization_plan, discovery_request, refresh_request, registration_request,
    revoke_request, session_from_refresh, session_from_token, session_server,
    session_should_refresh, token_request,
};
pub use oauth::{
    authorization_url, callback_code, discovery_url, refresh_token_body, registration_body,
    revoke_token_body, token_body,
};
pub use url::{normalize_server_url, validate_discovery};

pub type Result<T> = std::result::Result<T, String>;

pub fn wire(result: Result<String>) -> String {
    match result {
        Ok(value) => format!("ok:{value}"),
        Err(error) => format!("error:{error}"),
    }
}
