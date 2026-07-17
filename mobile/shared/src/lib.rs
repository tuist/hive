use std::ffi::{CStr, CString};
use std::os::raw::c_char;

mod core;

#[cfg(target_os = "android")]
mod android;

#[no_mangle]
pub unsafe extern "C" fn hive_mobile_authorization_start(
    server: *const c_char,
    redirect_uri: *const c_char,
    state: *const c_char,
    verifier: *const c_char,
) -> *mut c_char {
    let result = read_many(&[server, redirect_uri, state, verifier]).and_then(|values| {
        core::authorization_start(&values[0], &values[1], &values[2], &values[3])
    });
    to_c_string(core::wire(result))
}

#[no_mangle]
pub unsafe extern "C" fn hive_mobile_callback_start(
    callback_url: *const c_char,
    pending: *const c_char,
) -> *mut c_char {
    binary(callback_url, pending, core::callback_start)
}

#[no_mangle]
pub unsafe extern "C" fn hive_mobile_resource_start(
    session: *const c_char,
    resource: *const c_char,
    now: *const c_char,
) -> *mut c_char {
    ternary(session, resource, now, core::resource_start)
}

#[no_mangle]
pub unsafe extern "C" fn hive_mobile_client_continue(
    continuation: *const c_char,
    response: *const c_char,
    status: *const c_char,
    now: *const c_char,
) -> *mut c_char {
    let result = read_many(&[continuation, response, status, now])
        .and_then(|values| core::continue_client(&values[0], &values[1], &values[2], &values[3]));
    to_c_string(core::wire(result))
}

#[no_mangle]
pub unsafe extern "C" fn hive_mobile_sign_out_start(session: *const c_char) -> *mut c_char {
    unary(session, core::sign_out_start)
}

#[no_mangle]
pub unsafe extern "C" fn hive_mobile_session_server(session: *const c_char) -> *mut c_char {
    unary(session, core::session_server)
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
