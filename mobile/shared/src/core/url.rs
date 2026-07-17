use super::Result;

#[derive(Debug, PartialEq, Eq)]
struct ParsedUrl {
    origin: String,
    remainder: String,
}

pub fn normalize_server_url(input: &str) -> Result<String> {
    let parsed = parse_absolute_url(input.trim())?;
    if !parsed.remainder.is_empty() && parsed.remainder != "/" {
        return Err("Enter the Hive deployment address without a path.".to_string());
    }
    Ok(parsed.origin)
}

pub fn validate_discovery(
    server: &str,
    issuer: &str,
    authorization_endpoint: &str,
    token_endpoint: &str,
    registration_endpoint: &str,
    revocation_endpoint: &str,
) -> Result<String> {
    let normalized_server = normalize_server_url(server)?;
    let normalized_issuer = normalize_server_url(issuer)?;

    if normalized_server != normalized_issuer {
        return Err("The authorization server issuer does not match the Hive address.".to_string());
    }

    for (name, endpoint) in [
        ("authorization", authorization_endpoint),
        ("token", token_endpoint),
        ("registration", registration_endpoint),
        ("revocation", revocation_endpoint),
    ] {
        let parsed = parse_absolute_url(endpoint)?;
        if parsed.origin != normalized_server || parsed.remainder.is_empty() {
            return Err(format!(
                "The {name} endpoint does not belong to this Hive deployment."
            ));
        }
    }

    Ok(normalized_server)
}

fn parse_absolute_url(input: &str) -> Result<ParsedUrl> {
    if input.is_empty() || input.chars().any(char::is_whitespace) {
        return Err("Enter a valid Hive address.".to_string());
    }

    let (scheme, after_scheme) = input
        .split_once("://")
        .ok_or_else(|| "The Hive address must start with https://.".to_string())?;
    let scheme = scheme.to_ascii_lowercase();
    if scheme != "https" && scheme != "http" {
        return Err("The Hive address must use https.".to_string());
    }

    let authority_end = after_scheme
        .find(['/', '?', '#'])
        .unwrap_or(after_scheme.len());
    let authority = &after_scheme[..authority_end];
    let remainder = &after_scheme[authority_end..];

    if authority.is_empty() || authority.contains('@') || remainder.contains('#') {
        return Err("Enter a valid Hive address.".to_string());
    }

    let (host, normalized_authority) = normalize_authority(authority)?;
    if scheme == "http" && !is_local_development_host(&host) {
        return Err("Use https for non-local Hive deployments.".to_string());
    }

    Ok(ParsedUrl {
        origin: format!("{scheme}://{normalized_authority}"),
        remainder: remainder.to_string(),
    })
}

fn normalize_authority(authority: &str) -> Result<(String, String)> {
    let (host, port) = if authority.starts_with('[') {
        let closing = authority
            .find(']')
            .ok_or_else(|| "Enter a valid Hive address.".to_string())?;
        let host = &authority[..=closing];
        let suffix = &authority[closing + 1..];
        let port = if suffix.is_empty() {
            None
        } else {
            Some(
                suffix
                    .strip_prefix(':')
                    .ok_or_else(|| "Enter a valid Hive address.".to_string())?,
            )
        };
        (host, port)
    } else {
        match authority.rsplit_once(':') {
            Some((host, port)) if !host.contains(':') => (host, Some(port)),
            _ => (authority, None),
        }
    };

    let host = host.to_ascii_lowercase();
    if host.is_empty()
        || (!host.starts_with('[')
            && !host
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'-')))
    {
        return Err("Enter a valid Hive address.".to_string());
    }

    let normalized_port = match port {
        Some("") => return Err("Enter a valid Hive address.".to_string()),
        Some(value) => {
            let parsed: u16 = value
                .parse()
                .map_err(|_| "Enter a valid Hive address.".to_string())?;
            Some(parsed)
        }
        None => None,
    };

    let authority = match normalized_port {
        Some(port) => format!("{host}:{port}"),
        None => host.clone(),
    };
    Ok((host, authority))
}

fn is_local_development_host(host: &str) -> bool {
    matches!(host, "localhost" | "127.0.0.1" | "[::1]" | "10.0.2.2")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_deployment_origins() {
        assert_eq!(
            normalize_server_url(" HTTPS://Hive.Example.com/ ").unwrap(),
            "https://hive.example.com"
        );
        assert_eq!(
            normalize_server_url("http://127.0.0.1:4421").unwrap(),
            "http://127.0.0.1:4421"
        );
    }

    #[test]
    fn rejects_insecure_remote_and_path_addresses() {
        assert_eq!(
            normalize_server_url("http://hive.example.com").unwrap_err(),
            "Use https for non-local Hive deployments."
        );
        assert!(normalize_server_url("https://hive.example.com/login").is_err());
    }

    #[test]
    fn requires_discovered_endpoints_to_stay_on_the_issuer() {
        assert!(validate_discovery(
            "https://hive.example.com",
            "https://hive.example.com",
            "https://hive.example.com/oauth2/authorize",
            "https://hive.example.com/oauth2/token",
            "https://hive.example.com/oauth2/register",
            "https://hive.example.com/oauth2/revoke",
        )
        .is_ok());

        assert!(validate_discovery(
            "https://hive.example.com",
            "https://hive.example.com",
            "https://attacker.example/oauth2/authorize",
            "https://hive.example.com/oauth2/token",
            "https://hive.example.com/oauth2/register",
            "https://hive.example.com/oauth2/revoke",
        )
        .is_err());
    }
}
