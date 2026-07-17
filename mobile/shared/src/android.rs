use std::ffi::{c_char, c_void, CStr, CString};
use std::mem;
use std::ptr;

use crate::core;

type JniEnv = *mut *const c_void;
type JString = *mut c_void;

const NEW_STRING_UTF: usize = 167;
const GET_STRING_UTF_CHARS: usize = 169;
const RELEASE_STRING_UTF_CHARS: usize = 170;

#[no_mangle]
pub unsafe extern "system" fn Java_dev_tuist_hive_SharedCore_mobileDiscoveryRequest(
    env: JniEnv,
    _class: *mut c_void,
    input: JString,
) -> JString {
    unary(env, input, core::discovery_request)
}

#[no_mangle]
pub unsafe extern "system" fn Java_dev_tuist_hive_SharedCore_mobileRegistrationRequest(
    env: JniEnv,
    _class: *mut c_void,
    server: JString,
    discovery_response: JString,
    redirect_uri: JString,
) -> JString {
    many(env, &[server, discovery_response, redirect_uri], |values| {
        core::registration_request(&values[0], &values[1], &values[2])
    })
}

#[no_mangle]
pub unsafe extern "system" fn Java_dev_tuist_hive_SharedCore_mobileAuthorizationPlan(
    env: JniEnv,
    _class: *mut c_void,
    server: JString,
    discovery_response: JString,
    registration_response: JString,
    redirect_uri: JString,
    state: JString,
    verifier: JString,
) -> JString {
    many(
        env,
        &[
            server,
            discovery_response,
            registration_response,
            redirect_uri,
            state,
            verifier,
        ],
        |values| {
            core::authorization_plan(
                &values[0], &values[1], &values[2], &values[3], &values[4], &values[5],
            )
        },
    )
}

#[no_mangle]
pub unsafe extern "system" fn Java_dev_tuist_hive_SharedCore_mobileTokenRequest(
    env: JniEnv,
    _class: *mut c_void,
    callback_url: JString,
    pending: JString,
) -> JString {
    many(env, &[callback_url, pending], |values| {
        core::token_request(&values[0], &values[1])
    })
}

#[no_mangle]
pub unsafe extern "system" fn Java_dev_tuist_hive_SharedCore_mobileSessionFromToken(
    env: JniEnv,
    _class: *mut c_void,
    pending: JString,
    token_response: JString,
    now: JString,
) -> JString {
    many(env, &[pending, token_response, now], |values| {
        core::session_from_token(&values[0], &values[1], &values[2])
    })
}

#[no_mangle]
pub unsafe extern "system" fn Java_dev_tuist_hive_SharedCore_mobileRefreshRequest(
    env: JniEnv,
    _class: *mut c_void,
    session: JString,
) -> JString {
    unary(env, session, core::refresh_request)
}

#[no_mangle]
pub unsafe extern "system" fn Java_dev_tuist_hive_SharedCore_mobileSessionFromRefresh(
    env: JniEnv,
    _class: *mut c_void,
    session: JString,
    token_response: JString,
    now: JString,
) -> JString {
    many(env, &[session, token_response, now], |values| {
        core::session_from_refresh(&values[0], &values[1], &values[2])
    })
}

#[no_mangle]
pub unsafe extern "system" fn Java_dev_tuist_hive_SharedCore_mobileRevokeRequest(
    env: JniEnv,
    _class: *mut c_void,
    session: JString,
) -> JString {
    unary(env, session, core::revoke_request)
}

#[no_mangle]
pub unsafe extern "system" fn Java_dev_tuist_hive_SharedCore_mobileApiRequest(
    env: JniEnv,
    _class: *mut c_void,
    session: JString,
    path: JString,
) -> JString {
    many(env, &[session, path], |values| {
        core::api_request(&values[0], &values[1])
    })
}

#[no_mangle]
pub unsafe extern "system" fn Java_dev_tuist_hive_SharedCore_mobileSessionShouldRefresh(
    env: JniEnv,
    _class: *mut c_void,
    session: JString,
    now: JString,
) -> JString {
    many(env, &[session, now], |values| {
        core::session_should_refresh(&values[0], &values[1])
    })
}

#[no_mangle]
pub unsafe extern "system" fn Java_dev_tuist_hive_SharedCore_mobileSessionServer(
    env: JniEnv,
    _class: *mut c_void,
    session: JString,
) -> JString {
    unary(env, session, core::session_server)
}

#[no_mangle]
pub unsafe extern "system" fn Java_dev_tuist_hive_SharedCore_normalizeServerUrl(
    env: JniEnv,
    _class: *mut c_void,
    input: JString,
) -> JString {
    unary(env, input, core::normalize_server_url)
}

#[no_mangle]
pub unsafe extern "system" fn Java_dev_tuist_hive_SharedCore_discoveryUrl(
    env: JniEnv,
    _class: *mut c_void,
    server: JString,
) -> JString {
    unary(env, server, core::discovery_url)
}

#[no_mangle]
pub unsafe extern "system" fn Java_dev_tuist_hive_SharedCore_registrationBody(
    env: JniEnv,
    _class: *mut c_void,
    client_name: JString,
    redirect_uri: JString,
) -> JString {
    many(env, &[client_name, redirect_uri], |values| {
        core::registration_body(&values[0], &values[1])
    })
}

#[no_mangle]
pub unsafe extern "system" fn Java_dev_tuist_hive_SharedCore_validateDiscovery(
    env: JniEnv,
    _class: *mut c_void,
    server: JString,
    issuer: JString,
    authorization_endpoint: JString,
    token_endpoint: JString,
    registration_endpoint: JString,
    revocation_endpoint: JString,
) -> JString {
    many(
        env,
        &[
            server,
            issuer,
            authorization_endpoint,
            token_endpoint,
            registration_endpoint,
            revocation_endpoint,
        ],
        |values| {
            core::validate_discovery(
                &values[0], &values[1], &values[2], &values[3], &values[4], &values[5],
            )
        },
    )
}

#[no_mangle]
pub unsafe extern "system" fn Java_dev_tuist_hive_SharedCore_authorizationUrl(
    env: JniEnv,
    _class: *mut c_void,
    endpoint: JString,
    client_id: JString,
    redirect_uri: JString,
    resource: JString,
    state: JString,
    verifier: JString,
) -> JString {
    many(
        env,
        &[endpoint, client_id, redirect_uri, resource, state, verifier],
        |values| {
            core::authorization_url(
                &values[0], &values[1], &values[2], &values[3], &values[4], &values[5],
            )
        },
    )
}

#[no_mangle]
pub unsafe extern "system" fn Java_dev_tuist_hive_SharedCore_tokenBody(
    env: JniEnv,
    _class: *mut c_void,
    code: JString,
    client_id: JString,
    redirect_uri: JString,
    resource: JString,
    verifier: JString,
) -> JString {
    many(
        env,
        &[code, client_id, redirect_uri, resource, verifier],
        |values| core::token_body(&values[0], &values[1], &values[2], &values[3], &values[4]),
    )
}

#[no_mangle]
pub unsafe extern "system" fn Java_dev_tuist_hive_SharedCore_callbackCode(
    env: JniEnv,
    _class: *mut c_void,
    callback_url: JString,
    redirect_uri: JString,
    expected_state: JString,
) -> JString {
    many(
        env,
        &[callback_url, redirect_uri, expected_state],
        |values| core::callback_code(&values[0], &values[1], &values[2]),
    )
}

#[no_mangle]
pub unsafe extern "system" fn Java_dev_tuist_hive_SharedCore_refreshTokenBody(
    env: JniEnv,
    _class: *mut c_void,
    refresh_token: JString,
    client_id: JString,
    resource: JString,
) -> JString {
    many(env, &[refresh_token, client_id, resource], |values| {
        core::refresh_token_body(&values[0], &values[1], &values[2])
    })
}

#[no_mangle]
pub unsafe extern "system" fn Java_dev_tuist_hive_SharedCore_revokeTokenBody(
    env: JniEnv,
    _class: *mut c_void,
    token: JString,
    client_id: JString,
) -> JString {
    many(env, &[token, client_id], |values| {
        core::revoke_token_body(&values[0], &values[1])
    })
}

unsafe fn unary(
    env: JniEnv,
    value: JString,
    operation: fn(&str) -> core::Result<String>,
) -> JString {
    many(env, &[value], |values| operation(&values[0]))
}

unsafe fn many(
    env: JniEnv,
    inputs: &[JString],
    operation: impl FnOnce(&[String]) -> core::Result<String>,
) -> JString {
    let values: core::Result<Vec<String>> = inputs
        .iter()
        .map(|input| read_java_string(env, *input))
        .collect();
    let result = values.and_then(|values| operation(&values));
    new_java_string(env, &core::wire(result))
}

unsafe fn read_java_string(env: JniEnv, value: JString) -> core::Result<String> {
    if value.is_null() {
        return Err("The native application passed a missing value.".to_string());
    }

    type GetChars = unsafe extern "system" fn(JniEnv, JString, *mut u8) -> *const c_char;
    type ReleaseChars = unsafe extern "system" fn(JniEnv, JString, *const c_char);
    let get_chars: GetChars = function(env, GET_STRING_UTF_CHARS);
    let release_chars: ReleaseChars = function(env, RELEASE_STRING_UTF_CHARS);
    let pointer = get_chars(env, value, ptr::null_mut());
    if pointer.is_null() {
        return Err("The native application passed invalid text.".to_string());
    }

    let result = CStr::from_ptr(pointer)
        .to_str()
        .map(str::to_string)
        .map_err(|_| "The native application passed invalid text.".to_string());
    release_chars(env, value, pointer);
    result
}

unsafe fn new_java_string(env: JniEnv, value: &str) -> JString {
    type NewString = unsafe extern "system" fn(JniEnv, *const c_char) -> JString;
    let new_string: NewString = function(env, NEW_STRING_UTF);
    let value =
        CString::new(value.replace('\0', "")).expect("sanitized strings contain no null bytes");
    new_string(env, value.as_ptr())
}

unsafe fn function<T: Copy>(env: JniEnv, index: usize) -> T {
    let table = *env as *const *const c_void;
    let pointer = *table.add(index);
    mem::transmute_copy(&pointer)
}
