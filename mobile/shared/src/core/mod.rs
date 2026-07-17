mod client;
mod json;
mod mobile;
mod oauth;
mod sha256;
mod url;

pub use client::{
    authorization_start, callback_start, continue_client, resource_start, sign_out_start,
};
pub use mobile::session_server;

pub type Result<T> = std::result::Result<T, String>;

pub fn wire(result: Result<String>) -> String {
    match result {
        Ok(value) => format!("ok:{value}"),
        Err(error) => format!("error:{error}"),
    }
}
