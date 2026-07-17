use std::ffi::{CStr, CString};
use std::os::raw::c_char;

mod core;

#[cfg(target_os = "android")]
mod android;

#[no_mangle]
pub unsafe extern "C" fn hive_mobile_discovery_request(input: *const c_char) -> *mut c_char {
    unary(input, core::discovery_request)
}

#[no_mangle]
pub unsafe extern "C" fn hive_mobile_registration_request(
    server: *const c_char,
    discovery_response: *const c_char,
    redirect_uri: *const c_char,
) -> *mut c_char {
    ternary(
        server,
        discovery_response,
        redirect_uri,
        core::registration_request,
    )
}

#[no_mangle]
pub unsafe extern "C" fn hive_mobile_authorization_plan(
    server: *const c_char,
    discovery_response: *const c_char,
    registration_response: *const c_char,
    redirect_uri: *const c_char,
    state: *const c_char,
    verifier: *const c_char,
) -> *mut c_char {
    let result = read_many(&[
        server,
        discovery_response,
        registration_response,
        redirect_uri,
        state,
        verifier,
    ])
    .and_then(|values| {
        core::authorization_plan(
            &values[0], &values[1], &values[2], &values[3], &values[4], &values[5],
        )
    });
    to_c_string(core::wire(result))
}

#[no_mangle]
pub unsafe extern "C" fn hive_mobile_token_request(
    callback_url: *const c_char,
    pending: *const c_char,
) -> *mut c_char {
    binary(callback_url, pending, core::token_request)
}

#[no_mangle]
pub unsafe extern "C" fn hive_mobile_session_from_token(
    pending: *const c_char,
    token_response: *const c_char,
    now: *const c_char,
) -> *mut c_char {
    ternary(pending, token_response, now, core::session_from_token)
}

#[no_mangle]
pub unsafe extern "C" fn hive_mobile_refresh_request(session: *const c_char) -> *mut c_char {
    unary(session, core::refresh_request)
}

#[no_mangle]
pub unsafe extern "C" fn hive_mobile_session_from_refresh(
    session: *const c_char,
    token_response: *const c_char,
    now: *const c_char,
) -> *mut c_char {
    ternary(session, token_response, now, core::session_from_refresh)
}

#[no_mangle]
pub unsafe extern "C" fn hive_mobile_revoke_request(session: *const c_char) -> *mut c_char {
    unary(session, core::revoke_request)
}

#[no_mangle]
pub unsafe extern "C" fn hive_mobile_api_request(
    session: *const c_char,
    path: *const c_char,
) -> *mut c_char {
    binary(session, path, core::api_request)
}

#[no_mangle]
pub unsafe extern "C" fn hive_mobile_session_should_refresh(
    session: *const c_char,
    now: *const c_char,
) -> *mut c_char {
    binary(session, now, core::session_should_refresh)
}

#[no_mangle]
pub unsafe extern "C" fn hive_mobile_session_server(session: *const c_char) -> *mut c_char {
    unary(session, core::session_server)
}

#[no_mangle]
pub unsafe extern "C" fn hive_normalize_server_url(input: *const c_char) -> *mut c_char {
    unary(input, core::normalize_server_url)
}

#[no_mangle]
pub unsafe extern "C" fn hive_discovery_url(server: *const c_char) -> *mut c_char {
    unary(server, core::discovery_url)
}

#[no_mangle]
pub unsafe extern "C" fn hive_registration_body(
    client_name: *const c_char,
    redirect_uri: *const c_char,
) -> *mut c_char {
    binary(client_name, redirect_uri, core::registration_body)
}

#[no_mangle]
pub unsafe extern "C" fn hive_validate_discovery(
    server: *const c_char,
    issuer: *const c_char,
    authorization_endpoint: *const c_char,
    token_endpoint: *const c_char,
    registration_endpoint: *const c_char,
    revocation_endpoint: *const c_char,
) -> *mut c_char {
    let result = read_many(&[
        server,
        issuer,
        authorization_endpoint,
        token_endpoint,
        registration_endpoint,
        revocation_endpoint,
    ])
    .and_then(|values| {
        core::validate_discovery(
            &values[0], &values[1], &values[2], &values[3], &values[4], &values[5],
        )
    });
    to_c_string(core::wire(result))
}

#[no_mangle]
pub unsafe extern "C" fn hive_authorization_url(
    endpoint: *const c_char,
    client_id: *const c_char,
    redirect_uri: *const c_char,
    resource: *const c_char,
    state: *const c_char,
    verifier: *const c_char,
) -> *mut c_char {
    let result = read_many(&[endpoint, client_id, redirect_uri, resource, state, verifier])
        .and_then(|values| {
            core::authorization_url(
                &values[0], &values[1], &values[2], &values[3], &values[4], &values[5],
            )
        });
    to_c_string(core::wire(result))
}

#[no_mangle]
pub unsafe extern "C" fn hive_token_body(
    code: *const c_char,
    client_id: *const c_char,
    redirect_uri: *const c_char,
    resource: *const c_char,
    verifier: *const c_char,
) -> *mut c_char {
    let result =
        read_many(&[code, client_id, redirect_uri, resource, verifier]).and_then(|values| {
            core::token_body(&values[0], &values[1], &values[2], &values[3], &values[4])
        });
    to_c_string(core::wire(result))
}

#[no_mangle]
pub unsafe extern "C" fn hive_callback_code(
    callback_url: *const c_char,
    expected_redirect_uri: *const c_char,
    expected_state: *const c_char,
) -> *mut c_char {
    let result = read_many(&[callback_url, expected_redirect_uri, expected_state])
        .and_then(|values| core::callback_code(&values[0], &values[1], &values[2]));
    to_c_string(core::wire(result))
}

#[no_mangle]
pub unsafe extern "C" fn hive_refresh_token_body(
    refresh_token: *const c_char,
    client_id: *const c_char,
    resource: *const c_char,
) -> *mut c_char {
    let result = read_many(&[refresh_token, client_id, resource])
        .and_then(|values| core::refresh_token_body(&values[0], &values[1], &values[2]));
    to_c_string(core::wire(result))
}

#[no_mangle]
pub unsafe extern "C" fn hive_revoke_token_body(
    token: *const c_char,
    client_id: *const c_char,
) -> *mut c_char {
    binary(token, client_id, core::revoke_token_body)
}

/// # Safety
///
/// `value` must be null or a pointer returned by this library that has not
/// already been freed.
#[no_mangle]
pub unsafe extern "C" fn hive_string_free(value: *mut c_char) {
    if !value.is_null() {
        drop(CString::from_raw(value));
    }
}

unsafe fn unary(first: *const c_char, operation: fn(&str) -> core::Result<String>) -> *mut c_char {
    let result = read(first).and_then(|value| operation(&value));
    to_c_string(core::wire(result))
}

unsafe fn binary(
    first: *const c_char,
    second: *const c_char,
    operation: fn(&str, &str) -> core::Result<String>,
) -> *mut c_char {
    let result = read_many(&[first, second]).and_then(|values| operation(&values[0], &values[1]));
    to_c_string(core::wire(result))
}

unsafe fn ternary(
    first: *const c_char,
    second: *const c_char,
    third: *const c_char,
    operation: fn(&str, &str, &str) -> core::Result<String>,
) -> *mut c_char {
    let result = read_many(&[first, second, third])
        .and_then(|values| operation(&values[0], &values[1], &values[2]));
    to_c_string(core::wire(result))
}

unsafe fn read_many(values: &[*const c_char]) -> core::Result<Vec<String>> {
    values.iter().map(|value| read(*value)).collect()
}

unsafe fn read(value: *const c_char) -> core::Result<String> {
    if value.is_null() {
        return Err("The native application passed a missing value.".to_string());
    }
    CStr::from_ptr(value)
        .to_str()
        .map(str::to_string)
        .map_err(|_| "The native application passed invalid text.".to_string())
}

fn to_c_string(value: String) -> *mut c_char {
    CString::new(value.replace('\0', ""))
        .expect("sanitized strings contain no null bytes")
        .into_raw()
}
