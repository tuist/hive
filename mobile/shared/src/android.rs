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
pub unsafe extern "system" fn Java_dev_tuist_hive_SharedCore_mobileAuthorizationStart(
    env: JniEnv,
    _class: *mut c_void,
    server: JString,
    redirect_uri: JString,
    state: JString,
    verifier: JString,
) -> JString {
    many(env, &[server, redirect_uri, state, verifier], |values| {
        core::authorization_start(&values[0], &values[1], &values[2], &values[3])
    })
}

#[no_mangle]
pub unsafe extern "system" fn Java_dev_tuist_hive_SharedCore_mobileCallbackStart(
    env: JniEnv,
    _class: *mut c_void,
    callback_url: JString,
    pending: JString,
) -> JString {
    many(env, &[callback_url, pending], |values| {
        core::callback_start(&values[0], &values[1])
    })
}

#[no_mangle]
pub unsafe extern "system" fn Java_dev_tuist_hive_SharedCore_mobileResourceStart(
    env: JniEnv,
    _class: *mut c_void,
    session: JString,
    resource: JString,
    now: JString,
) -> JString {
    many(env, &[session, resource, now], |values| {
        core::resource_start(&values[0], &values[1], &values[2])
    })
}

#[no_mangle]
pub unsafe extern "system" fn Java_dev_tuist_hive_SharedCore_mobileClientContinue(
    env: JniEnv,
    _class: *mut c_void,
    continuation: JString,
    response: JString,
    status: JString,
    now: JString,
) -> JString {
    many(env, &[continuation, response, status, now], |values| {
        core::continue_client(&values[0], &values[1], &values[2], &values[3])
    })
}

#[no_mangle]
pub unsafe extern "system" fn Java_dev_tuist_hive_SharedCore_mobileSignOutStart(
    env: JniEnv,
    _class: *mut c_void,
    session: JString,
) -> JString {
    unary(env, session, core::sign_out_start)
}

#[no_mangle]
pub unsafe extern "system" fn Java_dev_tuist_hive_SharedCore_mobileSessionServer(
    env: JniEnv,
    _class: *mut c_void,
    session: JString,
) -> JString {
    unary(env, session, core::session_server)
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
