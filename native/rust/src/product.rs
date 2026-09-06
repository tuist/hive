//! Small product primitives shared by every platform target.
//!
//! Keep this module independent from project management, agent tools, and
//! inference providers so lightweight platform libraries can select it alone.

/// The product name used by Hive applications.
pub const APP_NAME: &str = "Hive";

/// The primary Tuist brand colour, represented as an RGB hexadecimal value.
pub const BRAND_COLOR: u32 = 0x6F2CFF;

pub(crate) const APP_NAME_C_STRING: &[u8] = b"Hive\0";

/// The authentication state shared by platform clients.
#[repr(i32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AuthenticationState {
    SignedOut = 0,
    Authenticating = 1,
    Authenticated = 2,
    Failed = 3,
}

impl AuthenticationState {
    pub const fn from_raw(value: i32) -> Option<Self> {
        match value {
            0 => Some(Self::SignedOut),
            1 => Some(Self::Authenticating),
            2 => Some(Self::Authenticated),
            3 => Some(Self::Failed),
            _ => None,
        }
    }
}

/// A product capability that a platform client may expose.
#[repr(i32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ProductCapability {
    LocalProjects = 0,
    LocalSessions = 1,
    RemoteSessions = 2,
    RemoteBuilds = 3,
}

impl ProductCapability {
    pub const fn from_raw(value: i32) -> Option<Self> {
        match value {
            0 => Some(Self::LocalProjects),
            1 => Some(Self::LocalSessions),
            2 => Some(Self::RemoteSessions),
            3 => Some(Self::RemoteBuilds),
            _ => None,
        }
    }
}

/// An event reported by a platform-specific authentication implementation.
#[repr(i32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AuthenticationEvent {
    RestoreUnauthenticated = 0,
    RestoreAuthenticated = 1,
    StartSignIn = 2,
    SignInSucceeded = 3,
    SignInFailed = 4,
    Cancelled = 5,
    SignOut = 6,
}

impl AuthenticationEvent {
    pub const fn from_raw(value: i32) -> Option<Self> {
        match value {
            0 => Some(Self::RestoreUnauthenticated),
            1 => Some(Self::RestoreAuthenticated),
            2 => Some(Self::StartSignIn),
            3 => Some(Self::SignInSucceeded),
            4 => Some(Self::SignInFailed),
            5 => Some(Self::Cancelled),
            6 => Some(Self::SignOut),
            _ => None,
        }
    }
}

/// Returns the shared product name.
pub const fn app_name() -> &'static str {
    APP_NAME
}

/// Returns the shared primary Tuist brand colour.
pub const fn brand_color() -> u32 {
    BRAND_COLOR
}

/// Applies an authentication event to the current shared authentication state.
pub fn authentication_state_after(
    state: AuthenticationState,
    event: AuthenticationEvent,
) -> AuthenticationState {
    match event {
        AuthenticationEvent::RestoreUnauthenticated | AuthenticationEvent::SignOut => {
            AuthenticationState::SignedOut
        }
        AuthenticationEvent::RestoreAuthenticated => AuthenticationState::Authenticated,
        AuthenticationEvent::StartSignIn
            if matches!(
                state,
                AuthenticationState::SignedOut | AuthenticationState::Failed
            ) =>
        {
            AuthenticationState::Authenticating
        }
        AuthenticationEvent::SignInSucceeded if state == AuthenticationState::Authenticating => {
            AuthenticationState::Authenticated
        }
        AuthenticationEvent::SignInFailed => AuthenticationState::Failed,
        AuthenticationEvent::Cancelled if state == AuthenticationState::Authenticating => {
            AuthenticationState::SignedOut
        }
        _ => state,
    }
}

/// Returns whether an account state may use a product capability.
pub fn is_capability_available(
    authentication_state: AuthenticationState,
    capability: ProductCapability,
) -> bool {
    match capability {
        ProductCapability::LocalProjects | ProductCapability::LocalSessions => true,
        ProductCapability::RemoteSessions | ProductCapability::RemoteBuilds => {
            authentication_state == AuthenticationState::Authenticated
        }
    }
}
