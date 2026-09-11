///|
/// Toolchain-independent number parsing.
///
/// `@strconv.from_str` changed its error behavior between core releases
/// (raising vs not), which broke type checking depending on the installed
/// toolchain. These hand-rolled parsers have a stable signature: they
/// accept an optional sign, decimal digits, and (for doubles) one decimal
/// point -- everything the CLI and the ffprobe integration ever need.

///|
pub(all) suberror ParseError {
  InvalidNumber(text~ : String)
} derive(Debug, Eq)

///|
fn digit(ch : Char) -> Int? {
  if ch >= '0' && ch <= '9' {
    Some(ch.to_int() - 48)
  } else {
    None
  }
}

///|
/// Sign char if present, then the rest of the string.

///|
fn split_sign(view : StringView) -> (Bool, StringView) {
  if view.length() > 0 {
    let first = view[0]
    if first == '-' {
      return (true, view[1:])
    }
    if first == '+' {
      return (false, view[1:])
    }
  }
  (false, view)
}

///|
pub fn parse_int(text : StringView) -> Int raise ParseError {
  let (neg, digits) = split_sign(text)
  if digits.length() == 0 {
    raise ParseError::InvalidNumber(text=text.to_owned())
  }
  let mut n = 0
  for ch in digits {
    match digit(ch) {
      Some(d) => {
        if n > (2147483647 - d) / 10 {
          raise ParseError::InvalidNumber(text=text.to_owned())
        }
        n = n * 10 + d
      }
      None => raise ParseError::InvalidNumber(text=text.to_owned())
    }
  }
  if neg {
    -n
  } else {
    n
  }
}

///|
/// Decimal double without exponent notation (CLI rates, durations).

///|
pub fn parse_double(text : StringView) -> Double raise ParseError {
  let (neg, body) = split_sign(text)
  let mut int_part = 0.0
  let mut frac = 0.0
  let mut scale = 0.1
  let mut seen_digit = false
  let mut seen_dot = false
  for ch in body {
    if ch == '.' {
      if seen_dot {
        raise ParseError::InvalidNumber(text=text.to_owned())
      }
      seen_dot = true
    } else {
      match digit(ch) {
        Some(d) => {
          seen_digit = true
          if seen_dot {
            frac = frac + d.to_double() * scale
            scale = scale / 10.0
          } else {
            int_part = int_part * 10.0 + d.to_double()
          }
        }
        None => raise ParseError::InvalidNumber(text=text.to_owned())
      }
    }
  }
  if !seen_digit {
    raise ParseError::InvalidNumber(text=text.to_owned())
  }
  let value = int_part + frac
  if neg {
    -value
  } else {
    value
  }
}
