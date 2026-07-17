use std::collections::BTreeMap;

use super::Result;

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Null,
    Boolean(bool),
    Number(i64),
    String(String),
    Array(Vec<Value>),
    Object(BTreeMap<String, Value>),
}

impl Value {
    pub fn object(input: &str) -> Result<BTreeMap<String, Value>> {
        match Parser::new(input).parse()? {
            Self::Object(value) => Ok(value),
            _ => Err(invalid_response()),
        }
    }

    pub fn string(&self) -> Option<&str> {
        match self {
            Self::String(value) => Some(value),
            _ => None,
        }
    }

    pub fn number(&self) -> Option<i64> {
        match self {
            Self::Number(value) => Some(*value),
            _ => None,
        }
    }
}

pub fn required_string(values: &BTreeMap<String, Value>, key: &str) -> Result<String> {
    values
        .get(key)
        .and_then(Value::string)
        .filter(|value| !value.is_empty())
        .map(str::to_string)
        .ok_or_else(invalid_response)
}

pub fn optional_string(values: &BTreeMap<String, Value>, key: &str) -> Result<Option<String>> {
    match values.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(Value::String(value)) if !value.is_empty() => Ok(Some(value.clone())),
        _ => Err(invalid_response()),
    }
}

pub fn optional_number(values: &BTreeMap<String, Value>, key: &str) -> Result<Option<i64>> {
    match values.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(value) => value.number().map(Some).ok_or_else(invalid_response),
    }
}

pub fn escape(value: &str) -> String {
    let mut output = String::new();
    for character in value.chars() {
        match character {
            '"' => output.push_str("\\\""),
            '\\' => output.push_str("\\\\"),
            '\n' => output.push_str("\\n"),
            '\r' => output.push_str("\\r"),
            '\t' => output.push_str("\\t"),
            value if value.is_control() => output.push_str(&format!("\\u{:04X}", value as u32)),
            value => output.push(value),
        }
    }
    output
}

fn invalid_response() -> String {
    "Hive returned a response the application could not read.".to_string()
}

struct Parser<'a> {
    bytes: &'a [u8],
    index: usize,
}

impl<'a> Parser<'a> {
    fn new(input: &'a str) -> Self {
        Self {
            bytes: input.as_bytes(),
            index: 0,
        }
    }

    fn parse(mut self) -> Result<Value> {
        let value = self.value()?;
        self.whitespace();
        if self.index != self.bytes.len() {
            return Err(invalid_response());
        }
        Ok(value)
    }

    fn value(&mut self) -> Result<Value> {
        self.whitespace();
        match self.peek() {
            Some(b'"') => self.string().map(Value::String),
            Some(b'{') => self.object(),
            Some(b'[') => self.array(),
            Some(b't') => self.literal(b"true", Value::Boolean(true)),
            Some(b'f') => self.literal(b"false", Value::Boolean(false)),
            Some(b'n') => self.literal(b"null", Value::Null),
            Some(b'-' | b'0'..=b'9') => self.number(),
            _ => Err(invalid_response()),
        }
    }

    fn object(&mut self) -> Result<Value> {
        self.expect(b'{')?;
        let mut values = BTreeMap::new();
        self.whitespace();
        if self.take(b'}') {
            return Ok(Value::Object(values));
        }
        loop {
            self.whitespace();
            let key = self.string()?;
            self.whitespace();
            self.expect(b':')?;
            if values.insert(key, self.value()?).is_some() {
                return Err(invalid_response());
            }
            self.whitespace();
            if self.take(b'}') {
                return Ok(Value::Object(values));
            }
            self.expect(b',')?;
        }
    }

    fn array(&mut self) -> Result<Value> {
        self.expect(b'[')?;
        let mut values = Vec::new();
        self.whitespace();
        if self.take(b']') {
            return Ok(Value::Array(values));
        }
        loop {
            values.push(self.value()?);
            self.whitespace();
            if self.take(b']') {
                return Ok(Value::Array(values));
            }
            self.expect(b',')?;
        }
    }

    fn string(&mut self) -> Result<String> {
        self.expect(b'"')?;
        let mut output = String::new();
        let mut start = self.index;
        while let Some(byte) = self.peek() {
            match byte {
                b'"' => {
                    output.push_str(self.text(start, self.index)?);
                    self.index += 1;
                    return Ok(output);
                }
                b'\\' => {
                    output.push_str(self.text(start, self.index)?);
                    self.index += 1;
                    let escaped = self.next().ok_or_else(invalid_response)?;
                    match escaped {
                        b'"' => output.push('"'),
                        b'\\' => output.push('\\'),
                        b'/' => output.push('/'),
                        b'b' => output.push('\u{0008}'),
                        b'f' => output.push('\u{000C}'),
                        b'n' => output.push('\n'),
                        b'r' => output.push('\r'),
                        b't' => output.push('\t'),
                        b'u' => output.push(self.unicode_escape()?),
                        _ => return Err(invalid_response()),
                    }
                    start = self.index;
                }
                0..=31 => return Err(invalid_response()),
                _ => self.index += 1,
            }
        }
        Err(invalid_response())
    }

    fn unicode_escape(&mut self) -> Result<char> {
        let first = self.hex_quad()?;
        let scalar = if (0xD800..=0xDBFF).contains(&first) {
            self.expect(b'\\')?;
            self.expect(b'u')?;
            let second = self.hex_quad()?;
            if !(0xDC00..=0xDFFF).contains(&second) {
                return Err(invalid_response());
            }
            0x10000 + (((first - 0xD800) as u32) << 10) + (second - 0xDC00) as u32
        } else {
            first as u32
        };
        char::from_u32(scalar).ok_or_else(invalid_response)
    }

    fn hex_quad(&mut self) -> Result<u16> {
        let mut value = 0_u16;
        for _ in 0..4 {
            value = (value << 4)
                | match self.next().ok_or_else(invalid_response)? {
                    byte @ b'0'..=b'9' => (byte - b'0') as u16,
                    byte @ b'a'..=b'f' => (byte - b'a' + 10) as u16,
                    byte @ b'A'..=b'F' => (byte - b'A' + 10) as u16,
                    _ => return Err(invalid_response()),
                };
        }
        Ok(value)
    }

    fn number(&mut self) -> Result<Value> {
        let start = self.index;
        self.take(b'-');
        while matches!(self.peek(), Some(b'0'..=b'9')) {
            self.index += 1;
        }
        if matches!(self.peek(), Some(b'.' | b'e' | b'E')) {
            return Err(invalid_response());
        }
        self.text(start, self.index)?
            .parse::<i64>()
            .map(Value::Number)
            .map_err(|_| invalid_response())
    }

    fn literal(&mut self, literal: &[u8], value: Value) -> Result<Value> {
        if self.bytes.get(self.index..self.index + literal.len()) == Some(literal) {
            self.index += literal.len();
            Ok(value)
        } else {
            Err(invalid_response())
        }
    }

    fn text(&self, start: usize, end: usize) -> Result<&str> {
        std::str::from_utf8(&self.bytes[start..end]).map_err(|_| invalid_response())
    }

    fn whitespace(&mut self) {
        while matches!(self.peek(), Some(b' ' | b'\n' | b'\r' | b'\t')) {
            self.index += 1;
        }
    }

    fn expect(&mut self, expected: u8) -> Result<()> {
        if self.take(expected) {
            Ok(())
        } else {
            Err(invalid_response())
        }
    }

    fn take(&mut self, expected: u8) -> bool {
        if self.peek() == Some(expected) {
            self.index += 1;
            true
        } else {
            false
        }
    }

    fn next(&mut self) -> Option<u8> {
        let value = self.peek()?;
        self.index += 1;
        Some(value)
    }

    fn peek(&self) -> Option<u8> {
        self.bytes.get(self.index).copied()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_nested_json_and_escaped_text() {
        let parsed =
            Value::object(r#"{"name":"Hive \uD83D\uDC1D","nested":{"ok":true},"items":[1,null]}"#)
                .unwrap();
        assert_eq!(required_string(&parsed, "name").unwrap(), "Hive 🐝");
    }

    #[test]
    fn rejects_duplicate_keys_and_trailing_input() {
        assert!(Value::object(r#"{"a":1,"a":2}"#).is_err());
        assert!(Value::object(r#"{"a":1}oops"#).is_err());
    }
}
